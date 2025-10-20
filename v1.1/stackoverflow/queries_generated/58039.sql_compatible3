WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 5, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2, 3)
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50 OR COUNT(c.Id) > 100
),
PostClosures AS (
    SELECT 
        ph.PostId,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents,
        STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasons
    FROM PostHistory ph
    JOIN CloseReasonTypes crt 
      ON crt.Id = CASE 
                    WHEN ph.Comment ~ '^\d+$' THEN CAST(ph.Comment AS INTEGER)
                    ELSE NULL
                  END
    WHERE ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.PostId
),
TagUsage AS (
    SELECT 
        raw.OwnerUserId AS OwnerUserId,
        raw.tag AS Tag,
        COUNT(*) AS TagCount
    FROM (
        SELECT
            p.OwnerUserId,
            TRIM(t) AS tag
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT s AS t
            FROM (
                SELECT
                    regexp_split_to_table(
                        regexp_replace(coalesce(p.Tags, ''), '^<|>$', '', 'g'),
                        '><'
                    ) AS s
            ) sub
        ) tagparts
    ) raw
    WHERE raw.tag IS NOT NULL AND raw.tag <> ''
    GROUP BY raw.OwnerUserId, raw.tag
)
SELECT 
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.TotalBadges,
    au.AvgQuestionScore,
    au.AvgAnswerScore,
    COALESCE(SUM(pc.CloseEvents), 0) AS TotalClosures,
    COALESCE(SUM(pc.ReopenEvents), 0) AS TotalReopens,
    (
      SELECT STRING_AGG(t.Tag || ' (' || CAST(t.TagCount AS VARCHAR) || ')', ', ' ORDER BY t.TagCount DESC)
      FROM TagUsage t
      WHERE t.OwnerUserId = au.Id AND t.TagCount > 5
    ) AS TopTags,
    RANK() OVER (ORDER BY (au.TotalPosts * 2 + au.TotalComments * 0.5 + au.TotalVotes * 0.1 + au.TotalBadges * 10) DESC) AS ActivityRank,
    au.Id
FROM ActiveUsers au
LEFT JOIN Posts p ON au.Id = p.OwnerUserId
LEFT JOIN PostClosures pc ON p.Id = pc.PostId
GROUP BY au.Id, au.DisplayName, au.Reputation, au.TotalPosts, au.TotalComments, au.TotalVotes, au.TotalBadges, au.AvgQuestionScore, au.AvgAnswerScore, au.Id
ORDER BY ActivityRank, au.Reputation DESC
LIMIT 50;