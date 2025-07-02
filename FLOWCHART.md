+----------+                   +------------------+
|          | daily schedule    |                  |
|  GitHub  +------------------>|  Check submodule |
| Actions  |                   |  updates in OS   |
+----+-----+                   +--------+---------+
     |                                   |
     | Changes found                     |
     +-----------------------------------+
     |                                   |
     V                                   V
+--------------------+        +--------------------------+
| Build & Push imgs  |        |  No updates              |
| (frontend, backend,|        |  -> exit                 |
| devops, etc)       |        +--------------------------+
+---------+----------+
          |
          V
+----------------------+
| Push to Docker Hub   |
+---------+------------+
          |
          V
+------------------------------+
| Trigger dispatch/workflow to |
| deploy DRAFT to Balena Cloud |
+---------+--------------------+
          |
          V
+-----------------------------+
| Devices w/ draft fleet pull |
| new images, run update      |
+---------+-------------------+
          |
          V
+-------------------+
| Human Tests Draft |
+----+--------------+
     | success / OK |
     V
+--------------------------------------------------+
| Manual "workflow_dispatch" or git tag/release    |
+--------------------+-----------------------------+
                     |
                     V
          +--------------------------+
          | Push official release to |
          | Balena Production Fleet  |
          +--------------------------+