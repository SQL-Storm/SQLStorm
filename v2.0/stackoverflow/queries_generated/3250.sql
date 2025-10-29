-- {"query": "3250.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2565} 

WITH RecentPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
),
UserBadges AS (
    SELECT
        u.Id                           AS UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date)                    AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
TagAggregates AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                 AS QuestionCount,
        AVG(p.Score)                AS AvgScore,
        MAX(p.CreationDate)         AS LatestQuestion
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
PostVoteCounts AS (
    SELECT
        ph.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM PostHistory ph
    LEFT JOIN Votes v
        ON v.PostId = ph.PostId
       AND v.VoteTypeId IN (2, 3)
    GROUP BY ph.PostId
)
SELECT
    u.Id                                           AS UserId,
    COALESCE(u.DisplayName, 'Anonymous')           AS DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    rp.TotalPosts,
    rp.AnswerCount,
    rp.AvgScore,
    rv.UpVotes,
    rv.DownVotes,
    CASE
        WHEN ub.GoldBadges > 0 THEN 'PowerUser'
        WHEN ub.SilverBadges > 0 THEN 'Experienced'
        ELSE 'Newbie'
    END                                            AS UserTier,
    STRING_AGG(DISTINCT ta.TagName, ', ') FILTER (WHERE ta.TagName IS NOT NULL) AS TopTags
FROM Users u
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(*)                                            AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END)     AS AnswerCount,
        AVG(COALESCE(Score,0))                               AS AvgScore
    FROM RecentPosts
    WHERE rn = 1
    GROUP BY OwnerUserId
) rp ON rp.OwnerUserId = u.Id
LEFT JOIN UserBadges ub ON ub.UserId = u.Id
LEFT JOIN PostVoteCounts rv ON rv.PostId = (
    SELECT p2.Id
    FROM Posts p2
    WHERE p2.OwnerUserId = u.Id
      AND p2.CreationDate = (
          SELECT MAX(p3.CreationDate)
          FROM Posts p3
          WHERE p3.OwnerUserId = u.Id
      )
    LIMIT 1
)
LEFT JOIN (
    SELECT
        pt.OwnerUserId,
        t.TagName
    FROM Posts pt
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM pt.Tags), '><')) AS raw_tag
    ) AS tags_raw
    LEFT JOIN Tags t ON t.TagName = tags_raw.raw_tag
) ta ON ta.OwnerUserId = u.Id
WHERE (u.Reputation > 1000 OR ub.GoldBadges IS NOT NULL)
  AND (rp.TotalPosts IS NOT NULL OR ub.SilverBadges > 0)
GROUP BY
    u.Id, u.DisplayName, u.Reputation,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    ub.LastBadgeDate, rp.TotalPosts, rp.AnswerCount,
    rp.AvgScore, rv.UpVotes, rv.DownVotes,
    UserTier
HAVING COUNT(*) FILTER (WHERE rp.TotalPosts > 5) > 0
ORDER BY u.Reputation DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    NULL                                         AS UserId,
    '--- Summary ---'                            AS DisplayName,
    NULL                                         AS Reputation,
    NULL, NULL, NULL,
    NULL,
    SUM(rp.TotalPosts)                           AS TotalPosts,
    SUM(rp.AnswerCount)                          AS AnswerCount,
    AVG(rp.AvgScore)                             AS AvgScore,
    SUM(rv.UpVotes)                              AS UpVotes,
    SUM(rv.DownVotes)                            AS DownVotes,
    NULL,
    NULL
FROM Users u
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(*)                                            AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END)     AS AnswerCount,
        AVG(COALESCE(Score,0))                               AS AvgScore
    FROM RecentPosts
    WHERE rn = 1
    GROUP BY OwnerUserId
) rp ON rp.OwnerUserId = u.Id
LEFT JOIN PostVoteCounts rv ON rv.PostId = rp.OwnerUserId;
