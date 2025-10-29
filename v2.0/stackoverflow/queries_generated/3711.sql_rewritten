-- {"query": "3711.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2168} 
WITH
    q_user_posts AS (
        SELECT u.Id AS UserId,
               u.DisplayName,
               u.Reputation,
               COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)               AS QuestionCount,
               COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)               AS AnswerCount,
               COALESCE(SUM(p.Score),0)                                 AS TotalScore,
               MAX(p.CreationDate)                                      AS LastPostDate
        FROM   Users u
        LEFT  JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    q_badges AS (
        SELECT b.UserId,
               COUNT(*)                                                    AS BadgeTotal,
               SUM(CASE b.Class WHEN 1 THEN 5 WHEN 2 THEN 3 ELSE 1 END)   AS BadgePoints,
               STRING_AGG(DISTINCT b.Name, ';')                           AS BadgeNames
        FROM   Badges b
        GROUP BY b.UserId
    ),
    q_recent_votes AS (
        SELECT v.UserId,
               MAX(v.CreationDate)                                         AS LastVoteDate,
               COUNT(*) FILTER (WHERE v.VoteTypeId = 2)                    AS UpVoteCount,
               COUNT(*) FILTER (WHERE v.VoteTypeId = 3)                    AS DownVoteCount
        FROM   Votes v
        GROUP BY v.UserId
    ),
    q_user_tags AS (
        SELECT p.OwnerUserId AS UserId,
               STRING_AGG(DISTINCT t.TagName, ',')                         AS TagList
        FROM   Posts p
        JOIN   LATERAL (
                 SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
               ) pt ON true
        JOIN   Tags t ON t.TagName = pt.tag
        WHERE  p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),
    q_combined AS (
        SELECT up.UserId,
               up.DisplayName,
               up.Reputation,
               up.QuestionCount,
               up.AnswerCount,
               up.TotalScore,
               up.LastPostDate,
               COALESCE(b.BadgeTotal,0)                                     AS BadgeTotal,
               COALESCE(b.BadgePoints,0)                                    AS BadgePoints,
               COALESCE(b.BadgeNames,'')                                    AS BadgeNames,
               COALESCE(rv.LastVoteDate, up.LastPostDate)                   AS ActivityDate,
               COALESCE(rv.UpVoteCount,0)                                   AS UpVoteCount,
               COALESCE(rv.DownVoteCount,0)                                 AS DownVoteCount,
               COALESCE(ut.TagList,'')                                      AS TagList,
               ROW_NUMBER() OVER (ORDER BY up.Reputation DESC NULLS LAST,
                                          up.TotalScore DESC)               AS Rank
        FROM   q_user_posts   up
        LEFT   JOIN q_badges        b  ON b.UserId = up.UserId
        LEFT   JOIN q_recent_votes  rv ON rv.UserId = up.UserId
        LEFT   JOIN q_user_tags     ut ON ut.UserId = up.UserId
    )
SELECT *
FROM   q_combined
WHERE  Rank <= 50

UNION ALL

SELECT *
FROM   q_combined
WHERE  Reputation IS NULL OR Reputation = 0

ORDER BY Rank ASC,
         Reputation DESC NULLS LAST;