-- {"query": "3326.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2517} 

WITH recent_questions AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           COALESCE(p.Tags, '') AS Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
),
user_vote_agg AS (
    SELECT u.Id AS UserId,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                             WHEN v.VoteTypeId = 3 THEN -1
                             ELSE 0 END),0) AS NetVoteScore,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id
),
tag_explosion AS (
    SELECT rq.Id      AS PostId,
           trim(both '<>' FROM unnest(string_to_array(rq.Tags, '><'))) AS Tag
    FROM recent_questions rq
    WHERE rq.Tags <> ''
),
tag_stats AS (
    SELECT t.Tag,
           COUNT(*)                         AS QuestionCount,
           SUM(rq.ViewCount)                AS TotalViews,
           AVG(rq.Score)                    AS AvgScore
    FROM tag_explosion t
    JOIN recent_questions rq ON rq.Id = t.PostId
    GROUP BY t.Tag
),
user_badge_counts AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
user_activity AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(uv.NetVoteScore,0)               AS NetVoteScore,
           COALESCE(ub.GoldBadges,0)                 AS GoldBadges,
           COALESCE(ub.SilverBadges,0)               AS SilverBadges,
           COALESCE(ub.BronzeBadges,0)               AS BronzeBadges,
           COUNT(DISTINCT rq.Id) FILTER (WHERE rq.OwnerUserId = u.Id) AS RecentQuestionCount,
           COUNT(DISTINCT c.Id) FILTER (WHERE c.UserId = u.Id)        AS CommentCount,
           ROW_NUMBER() OVER (ORDER BY (u.Reputation + COALESCE(uv.NetVoteScore,0)) DESC) AS RankByRepPlusVotes
    FROM Users u
    LEFT JOIN user_vote_agg uv   ON uv.UserId = u.Id
    LEFT JOIN user_badge_counts ub ON ub.UserId = u.Id
    LEFT JOIN recent_questions rq ON rq.OwnerUserId = u.Id
    LEFT JOIN Comments c          ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, uv.NetVoteScore, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
top_users AS (
    SELECT *
    FROM user_activity
    WHERE RankByRepPlusVotes <= 100
),
popular_tags AS (
    SELECT *
    FROM tag_stats
    WHERE QuestionCount >= 50
      AND AvgScore > 2
)
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.NetVoteScore,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.RecentQuestionCount,
    tu.CommentCount,
    tu.RankByRepPlusVotes,
    COALESCE(pt.Tag, 'N/A')            AS RepresentativeTag,
    COALESCE(pt.QuestionCount,0)       AS TagQuestionCount,
    COALESCE(pt.TotalViews,0)          AS TagTotalViews,
    COALESCE(pt.AvgScore,0)            AS TagAvgScore
FROM top_users tu
LEFT JOIN LATERAL (
    SELECT ts.Tag, ts.QuestionCount, ts.TotalViews, ts.AvgScore
    FROM popular_tags ts
    ORDER BY ts.QuestionCount DESC, ts.AvgScore DESC
    LIMIT 1
) pt ON TRUE

UNION ALL

SELECT
    NULL AS Id,
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS NetVoteScore,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS RecentQuestionCount,
    NULL AS CommentCount,
    NULL AS RankByRepPlusVotes,
    t.Tag,
    t.QuestionCount,
    t.TotalViews,
    t.AvgScore
FROM popular_tags t
WHERE t.QuestionCount = (SELECT MAX(QuestionCount) FROM popular_tags);
