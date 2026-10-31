package com.desertkun.brainout.menu;

import com.badlogic.gdx.Gdx;
import com.desertkun.brainout.BrainOutClient;
import com.desertkun.brainout.client.ClientController;
import com.desertkun.brainout.common.enums.DisconnectReason;
import com.desertkun.brainout.menu.popups.AlertPopup;

import java.io.File;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;

public final class LocalServerLauncher
{
    private static Process matchServer;
    private static Process freePlayServer;
    private static volatile boolean switching;
    private static volatile boolean localMatchSession;

    private LocalServerLauncher()
    {
    }

    public static void launchMatch()
    {
        launch(false);
    }

    public static void launchFreePlay()
    {
        launch(true);
    }

    public static boolean isLocalMatchSession()
    {
        return localMatchSession;
    }

    public static void returnToLobby()
    {
        if (switching)
            return;

        switching = true;
        localMatchSession = false;

        ClientController controller = BrainOutClient.ClientController;

        controller.disconnect(DisconnectReason.leave, () ->
        {
            controller.connect(
                "127.0.0.1",
                36555, 36556, 36557,
                null,
                true,
                -1,
                () ->
                {
                    switching = false;

                    Gdx.app.postRunnable(() ->
                        BrainOutClient.getInstance().topState().pushMenu(
                            new AlertPopup(
                                "Could not reconnect to local lobby. "
                                    + "Make sure the lobby server is running."
                            )
                        )
                    );
                }
            );

            switching = false;
        });
    }

    private static synchronized void launch(boolean freePlay)
    {
        if (switching)
            return;

        switching = true;

        final int tcp = freePlay ? 36575 : 36565;
        final int udp = freePlay ? 36576 : 36566;
        final int http = freePlay ? 36577 : 36567;

        final String logName = freePlay
            ? "local-freeplay-server.log"
            : "local-match-server.log";

        try
        {
            File clientDir = Gdx.files.local(".").file().getCanonicalFile();
            File serverDir = new File(clientDir.getParentFile(), "server");

            if (!new File(serverDir, "brainout-server.jar").isFile())
            {
                throw new IOException(
                    "brainout-server.jar not found in " + serverDir
                );
            }

            Process process = freePlay ? freePlayServer : matchServer;

            if (process == null || !process.isAlive())
            {
                ProcessBuilder builder;

                if (freePlay)
                {
                    builder = new ProcessBuilder(
                        "cmd.exe", "/c", "run.bat",
                        "no", tcp + "," + udp + "," + http,
                        "--mode", "free",
                        "--settings", "server-free.json",
                        "--map", "freeplay-maps.shuffle",
                        "--offline"
                    );

                    builder.environment().put("game_max_players", "4");
                }
                else
                {
                    builder = new ProcessBuilder(
                        "cmd.exe", "/c", "run.bat",
                        "no", tcp + "," + udp + "," + http,
                        "--settings", "server-settings.json",
                        "--maps", "maps-set.json",
                        "--offline"
                    );

                    builder.environment().put(
                        "server_settings",
                        "{\"bots\":8}"
                    );
                }

                builder.directory(serverDir);
                builder.redirectErrorStream(true);
                builder.redirectOutput(new File(serverDir, logName));

                process = builder.start();

                if (freePlay)
                {
                    freePlayServer = process;
                }
                else
                {
                    matchServer = process;
                }
            }

            final Process serverProcess = process;

            Thread waiter = new Thread(() ->
            {
                boolean ready = false;
                long deadline = System.currentTimeMillis() + 30000;

                while (System.currentTimeMillis() < deadline
                    && serverProcess.isAlive())
                {
                    try (Socket socket = new Socket())
                    {
                        socket.connect(
                            new InetSocketAddress("127.0.0.1", tcp),
                            300
                        );

                        ready = true;
                        break;
                    }
                    catch (IOException ignored)
                    {
                        // Server has not opened its TCP port yet.
                    }

                    try
                    {
                        Thread.sleep(250);
                    }
                    catch (InterruptedException e)
                    {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }

                if (ready)
                {
                    try
                    {
                        Thread.sleep(3000);
                    }
                    catch (InterruptedException e)
                    {
                        Thread.currentThread().interrupt();
                    }
                }

                final boolean serverReady = ready;

                Gdx.app.postRunnable(() ->
                {
                    if (!serverReady)
                    {
                        switching = false;

                        BrainOutClient.getInstance().topState().pushMenu(
                            new AlertPopup(
                                "Local server did not start. Check bin/server/"
                                    + logName
                            )
                        );

                        return;
                    }

                    ClientController controller =
                        BrainOutClient.ClientController;

                    controller.disconnect(DisconnectReason.leave, () ->
                    {
                        localMatchSession = !freePlay;

                        controller.connect(
                            "127.0.0.1",
                            tcp, udp, http,
                            null,
                            false,
                            -1,
                            () ->
                            {
                                localMatchSession = false;
                                switching = false;

                                Gdx.app.postRunnable(() ->
                                    BrainOutClient.getInstance().topState().pushMenu(
                                        new AlertPopup(
                                            "Could not connect to local server. "
                                                + "Check bin/server/" + logName
                                        )
                                    )
                                );
                            }
                        );

                        switching = false;
                    });
                });
            }, "BrainOutLocalServerWaiter");

            waiter.setDaemon(true);
            waiter.start();
        }
        catch (Exception e)
        {
            switching = false;

            String message = e.getMessage();

            Gdx.app.postRunnable(() ->
                BrainOutClient.getInstance().topState().pushMenu(
                    new AlertPopup(
                        "Could not start local server: " + message
                    )
                )
            );
        }
    }
}