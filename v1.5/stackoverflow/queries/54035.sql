-- {"query": "54035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2206} 
SELECT
    u.Id                                         AS UserId,
    u.DisplayName,
    u.Reputation,
    q.QuestionCount,
    q.AverageQuestionScore,
    a.AnswerCount,
    a.AverageAnswerScore,
    a.TotalAnswerUpVotes,
    a.TotalAnswerDownVotes,
    c.CommentCount,
    v.TotalVotesOnPosts,
    b.BadgeCount,
    ROW_NUMBER() OVER (ORDER BY
        u.Reputation DESC,
        a.TotalAnswerUpVotes DESC,
        b.BadgeCount DESC,
        q.QuestionCount DESC)                 AS Rank
FROM
    Users u
LEFT JOIN
    ( SELECT OwnerUserId                   AS UserId,
             COUNT(*)                       AS QuestionCount,
             AVG(Score)                      AS AverageQuestionScore
      FROM Posts
      WHERE PostTypeId = 1
      GROUP BY OwnerUserId ) q
      ON q.UserId = u.Id
LEFT JOIN
    ( SELECT ParentId                       AS UserId,
             COUNT(*)                       AS AnswerCount,
             AVG(Score)                      AS AverageAnswerScore,
             SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswerUpVotes,
             SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalAnswerDownVotes
      FROM Posts p
      JOIN Votes v
        ON v.PostId = p.Id
      WHERE PostTypeId = 2
      GROUP BY ParentId ) a
      ON a.UserId = u.Id
LEFT JOIN
    ( SELECT UserId,
             COUNT(*) AS CommentCount
      FROM Comments
      GROUP BY UserId ) c
      ON c.UserId = u.Id
LEFT JOIN
    ( SELECT UserId,
             COUNT(*) AS TotalVotesOnPosts
      FROM Votes
      GROUP BY UserId ) v
      ON v.UserId = u.Id
LEFT JOIN
    ( SELECT UserId,
             COUNT(*) AS BadgeCount
      FROM Badges
      GROUP BY UserId ) b
      ON b.UserId = u.Id
WHERE
    u.Reputation > 10000
ORDER BY
    Rank
LIMIT 50;