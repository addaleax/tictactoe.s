tictactoe: tictactoe.s
	$(CC) -Wl,--build-id=none -static -nostdlib -o tictactoe tictactoe.s
