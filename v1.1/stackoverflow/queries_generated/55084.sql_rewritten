-- {"query": "55084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1838} 
WITH question_posts AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.Score,
           p.CreationDate,
           p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
),
tag_expansion AS (
    SELECT qp.Id                                     AS PostId,
           qp.OwnerUserId,
           qp.Score,
           qp.CreationDate,
           TRIM(BOTH '<>' FROM t.tag_name)          AS TagName
    FROM question_posts qp
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(qp.Tags, '><')) AS t(tag_name)
),
tag_stats AS (
    SELECT te.TagName,
           COUNT(*)                         AS QuestionCount,
           SUM(te.Score)                    AS TotalQuestionScore,
           AVG(te.Score)                    AS AvgQuestionScore,
           COUNT(DISTINCT te.OwnerUserId)   AS DistinctAskUsers
    FROM tag_expansion te
    GROUP BY te.TagName
),
user_activity AS (
    SELECT u.Id                                          AS UserId,
           u.Reputation,
           COALESCE(b.BadgeCount,   0)                  AS BadgeCount,
           COALESCE(v.VoteCount,   0)                  AS VoteCount,
           COALESCE(c.CommentCount,0)                  AS CommentCount,
           COALESCE(a.AnswerCount, 0)                  AS AnswerCount
    FROM Users u
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS VoteCount
        FROM Votes
        GROUP BY UserId
    ) v ON v.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY UserId
    ) c ON c.UserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2                      -- answers
        GROUP BY OwnerUserId
    ) a ON a.OwnerUserId = u.Id
),
tag_user_scores AS (
    SELECT te.TagName,
           ua.UserId,
           SUM(te.Score)                                 AS UserQuestionScore,
           COUNT(*)                                      AS UserQuestionCount,
           ROW_NUMBER() OVER (PARTITION BY te.TagName ORDER BY SUM(te.Score) DESC) AS RankByScore,
           ROW_NUMBER() OVER (PARTITION BY te.TagName ORDER BY COUNT(*)   DESC) AS RankByCount
    FROM tag_expansion te
    JOIN user_activity ua ON ua.UserId = te.OwnerUserId
    GROUP BY te.TagName, ua.UserId
)
SELECT ts.TagName,
       ts.QuestionCount,
       ts.TotalQuestionScore,
       ts.AvgQuestionScore,
       ts.DistinctAskUsers,
       tus.UserId,
       tus.UserQuestionCount,
       tus.UserQuestionScore,
       ua.Reputation,
       ua.BadgeCount,
       ua.VoteCount,
       ua.CommentCount,
       ua.AnswerCount,
       tus.RankByScore,
       tus.RankByCount
FROM tag_stats ts
JOIN tag_user_scores tus
      ON tus.TagName = ts.TagName
     AND tus.RankByScore <= 5                      -- top 5 users per tag by question score
JOIN user_activity ua
      ON ua.UserId = tus.UserId
ORDER BY ts.TagName, tus.RankByScore;