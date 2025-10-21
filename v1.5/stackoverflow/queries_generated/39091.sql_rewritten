-- {"query": "39091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2878} 
WITH user_activity AS (
    SELECT
        u.Id                       AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)   AS QCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)   AS ACount,
        SUM(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE 0 END) AS TotalScore,
        COUNT(DISTINCT c.Id)                                      AS CommentsMade,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END)   AS UpVotesGiven
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    LEFT JOIN Votes    v ON v.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName
),
top_users AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (ORDER BY ua.TotalScore DESC) AS UserRank
    FROM user_activity ua
),
topic_trends AS (
    SELECT
        tag AS Topic,
        COUNT(*)           AS PostsCount,
        AVG(ViewCount)     AS AvgViews,
        SUM(Score)         AS ScoreSum
    FROM (
        SELECT
            p.ViewCount,
            p.Score,
            unnest(string_to_array(trim(both '<>' FROM p.Tags),'><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    ) t
    GROUP BY tag
),
badge_breakdown AS (
    SELECT
        b.UserId,
        COUNT(*)                                       AS BadgeCount,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)    AS HasGold,
        MAX(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)    AS HasSilver,
        MAX(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)    AS HasBronze
    FROM Badges b
    GROUP BY b.UserId
),
answers_response_time AS (
    SELECT
        q.OwnerUserId                                AS AskerId,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)))/3600
                                                    AS AvgResponseHours
    FROM Posts q
    JOIN Posts a
      ON a.ParentId = q.Id
     AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
    GROUP BY q.OwnerUserId
),
user_topics AS (
    SELECT
        p.OwnerUserId AS UserId,
        unnest(string_to_array(trim(both '<>' FROM p.Tags),'><')) AS Topic
    FROM Posts p
    WHERE p.PostTypeId = 1
),
user_topic_stats AS (
    SELECT
        ut.UserId,
        ut.Topic,
        tt.PostsCount,
        tt.AvgViews,
        tt.ScoreSum
    FROM user_topics ut
    LEFT JOIN topic_trends tt
      ON tt.Topic = ut.Topic
)
SELECT
    tu.UserRank,
    tu.DisplayName,
    tu.QCount,
    tu.ACount,
    tu.TotalScore,
    tu.CommentsMade,
    tu.UpVotesGiven,
    COALESCE(br.BadgeCount,0)                AS BadgeCount,
    COALESCE(br.HasGold,0)                   AS HasGold,
    COALESCE(br.HasSilver,0)                 AS HasSilver,
    COALESCE(br.HasBronze,0)                 AS HasBronze,
    art.AvgResponseHours,
    uts.Topic,
    uts.PostsCount,
    uts.AvgViews,
    uts.ScoreSum
FROM top_users tu
LEFT JOIN badge_breakdown      br  ON br.UserId = tu.UserId
LEFT JOIN answers_response_time art ON art.AskerId = tu.UserId
LEFT JOIN user_topic_stats     uts ON uts.UserId = tu.UserId
WHERE tu.UserRank <= 50
ORDER BY tu.TotalScore DESC, uts.ScoreSum DESC
LIMIT 50;