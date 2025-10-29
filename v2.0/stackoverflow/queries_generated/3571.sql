-- {"query": "3571.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2278} 

WITH top_questions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
      AND p.Tags IS NOT NULL
      AND p.Tags <> ''
),
user_badges AS (
    SELECT 
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
recent_votes AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod'      THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod'    THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
),
tag_stats AS (
    SELECT 
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag,
        COUNT(*)                                            AS QuestionCount,
        AVG(p.Score)                                        AS AvgScore,
        MAX(p.ViewCount)                                    AS MaxViews
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY Tag
),
user_activity AS (
    SELECT 
        u.Id,
        COALESCE(qc.QuestionCount,0) + COALESCE(ac.AnswerCount,0) AS TotalContributions,
        GREATEST(
            COALESCE(u.LastAccessDate,      TIMESTAMP '1970-01-01'),
            COALESCE(lc.LastCommentDate,   TIMESTAMP '1970-01-01'),
            COALESCE(rv.LastVoteDate,      TIMESTAMP '1970-01-01')
        ) AS RecentActivity
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) qc ON qc.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) ac ON ac.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, MAX(CreationDate) AS LastCommentDate
        FROM Comments
        GROUP BY UserId
    ) lc ON lc.UserId = u.Id
    LEFT JOIN recent_votes rv ON rv.PostId = (
        SELECT Id
        FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
),
final AS (
    SELECT 
        tq.Id                                   AS QuestionId,
        tq.Title,
        tq.Score,
        tq.CreationDate,
        u.DisplayName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        rv.UpVotes,
        rv.DownVotes,
        t.Tag,
        ts.QuestionCount                        AS TagQuestionCount,
        ts.AvgScore                             AS TagAvgScore,
        ua.TotalContributions,
        ROW_NUMBER() OVER (PARTITION BY t.Tag ORDER BY tq.Score DESC) AS TagRank,
        CASE 
            WHEN tq.CreationDate < CURRENT_DATE - INTERVAL '5 years' THEN 'Legacy'
            WHEN tq.Score > 100                                           THEN 'Hot'
            ELSE                                                          'Normal'
        END AS Category
    FROM top_questions tq
    LEFT JOIN Users u               ON u.Id = tq.OwnerUserId
    LEFT JOIN user_badges ub        ON ub.UserId = u.Id
    LEFT JOIN recent_votes rv       ON rv.PostId = tq.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(tq.Tags, 2, LENGTH(tq.Tags)-2), '><')) AS Tag
    ) t ON TRUE
    LEFT JOIN tag_stats ts          ON ts.Tag = t.Tag
    LEFT JOIN user_activity ua      ON ua.Id = u.Id
    WHERE tq.rn <= 1000
),
unioned AS (
    SELECT QuestionId, Title, Score, Category FROM final WHERE Category = 'Hot'
    UNION ALL
    SELECT QuestionId, Title, Score, Category FROM final WHERE Category = 'Legacy' AND Score < 0
    UNION ALL
    SELECT QuestionId, Title, Score, Category FROM final WHERE Category = 'Normal'  AND TagRank <= 5
)
SELECT *
FROM unioned
ORDER BY Score DESC, QuestionId
LIMIT 200;
