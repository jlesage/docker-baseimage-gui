package main

import (
	"github.com/gorilla/websocket"
	"github.com/vmihailenco/msgpack/v5"
)

func writeMessagePack(conn *websocket.Conn, data interface{}) error {
	// Encode the data.
	encodedData, err := msgpack.Marshal(data)
	if err != nil {
		return err
	}

	// Send the data.
	return conn.WriteMessage(websocket.BinaryMessage, encodedData)
}

func readMessagePack(conn *websocket.Conn, data interface{}) error {
	// Receive data from WebSocket.
	_, msgData, err := conn.ReadMessage()
	if err != nil {
		return err
	}

	// Decode the MessagePack data.
	return msgpack.Unmarshal(msgData, data)
}
