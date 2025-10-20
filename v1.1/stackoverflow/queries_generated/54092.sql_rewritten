-- {"query": "54092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1701} 
WITH UserPostStats AS (
    SELECT u.id AS uid,
           u.displayname,
           u.reputation,
           SUM(CASE WHEN p.posttypeid = 1 THEN 1 ELSE 0 END) AS qcnt,
           SUM(CASE WHEN p.posttypeid = 2 THEN 1 ELSE 0 END) AS acnt,
           MAX(p.score) AS maxscore,
           AVG(p.score) FILTER (WHERE p.posttypeid = 1) AS avgqscore
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),
TagUsage AS (
    SELECT p.owneruserid AS uid,
           tag AS tagname,
           COUNT(*) AS cnt
    FROM posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
                substring(p.tags from 2 for length(p.tags)-2),
                '><')) AS tag
    ) AS t
    WHERE p.posttypeid = 1
    GROUP BY p.owneruserid, tag
),
TopTag AS (
    SELECT uid,
           tagname,
           cnt,
           ROW_NUMBER() OVER (PARTITION BY uid ORDER BY cnt DESC) AS rn
    FROM TagUsage
),
CloseVotes AS (
    SELECT ph.postid,
           COUNT(*) AS cv
    FROM posthistory ph
    WHERE ph.posthistorytypeid = 10
    GROUP BY ph.postid
)
SELECT ups.uid,
       ups.displayname,
       ups.reputation,
       ups.qcnt,
       ups.acnt,
       ups.maxscore,
       ROUND(ups.avgqscore, 2) AS avgqscore,
       tt.tagname AS top_tag,
       tt.cnt AS top_tag_usage,
       COALESCE(SUM(cv), 0) AS close_votes_received
FROM UserPostStats ups
JOIN TopTag tt ON ups.uid = tt.uid AND tt.rn = 1
LEFT JOIN posts p ON p.owneruserid = ups.uid
LEFT JOIN CloseVotes cv ON cv.postid = p.id
GROUP BY ups.uid,
         ups.displayname,
         ups.reputation,
         ups.qcnt,
         ups.acnt,
         ups.maxscore,
         ups.avgqscore,
         tt.tagname,
         tt.cnt
ORDER BY ups.reputation DESC
LIMIT 100;