module apn.connection;

import vibe.d;

import apn.settings;
import apn.binarynotification;

///
class APNConnection
{
	private immutable APNSettings	m_options;

private:
	TCPConnection	m_tcp;
	SSLStream		m_sslStream;
	ubyte[]			m_receiveBuff = new ubyte[64];

	BinaryNotification[] m_sent;
	BinaryNotification	m_current;

public:

	///
	@property bool isConnected() const {return m_sslStream !is null && m_tcp !is null;}
	///
	@property bool isBusy() const { return m_current !is null; }

	///
	this(APNSettings _options)
	{
		m_options = _options;

		connect();
	}

	///
	void send(BinaryNotification _msg)
	{
		if(isBusy)
		{
			logError("trying to use busy connection");
			return;
		}

		m_current = _msg;

		runTask(&sendTask);
	}

private:

	///
	void connect()
	{
		m_tcp = connectTCP(m_options.address, m_options.port);
		m_tcp.tcpNoDelay = true;

		auto sslctx = new SSLContext(SSLContextKind.client);
		sslctx.useCertificateChainFile(m_options.cert);
		sslctx.usePrivateKeyFile(m_options.key);

		m_sslStream = new SSLStream(m_tcp, sslctx);

		logInfo("connected");

		runTask(&receiveTask);
	}

	///
	void shutdown()
	{
		try
		{
			if(m_sslStream !is null && m_tcp !is null && m_tcp.connected)
			{
				m_sslStream.finalize();
				m_tcp.close();
			}
		}
		catch(Exception e)
			logError("error shutting down: %s",e);

		m_tcp = null;
		m_sslStream = null;
	}

	///
	void receiveTask()
	{
		logInfo("start receiving");

		while(isConnected)
		{
			if(m_tcp.waitForData(5.seconds))
			{
				if(m_sslStream.dataAvailableForRead)
				{		
					m_receiveBuff.length = 6;

					{
						try m_sslStream.read(m_receiveBuff);
						catch(Exception e)
							logInfo("error on reading error: %s",e);
					}

					parseError(m_receiveBuff);

					shutdown();

					return;
				}
			}

			yield();
		}
	}

	///
	void parseError(ubyte[] _buffer)
	{
		import std.bitmanip:read;

		//logInfo("result error: %s", _buffer);

		if(_buffer.length > 0)
		{
			auto cmd = _buffer.read!ubyte;
		
			if(cmd == 8)
			{
				auto status = _buffer.read!ubyte;
		
				auto id = _buffer.read!uint;
		
				logError("result error! status: %s id: %s", status, id);
			}
			else
				logError("got unknown result error: %s", _buffer);
		}
	}

	///
	void sendTask()
	{
		if(m_current !is null)
		{
			//logInfo("sending %s bytes", m_current.data.length);

			m_sslStream.write(m_current.data);

			m_sent ~= m_current;

			m_current = null;
		}
	}
}