-- {"query": "2769.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1382}
WITH RECURSIVE RecursiveTagCounts AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        t.WikiPostId,
        row_number() OVER (ORDER BY t.Count DESC, t.TagName) AS Rank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
    UNION ALL
    SELECT
        r.TagId,
        r.TagName,
        r.Count,
        r.WikiPostId,
        r.Rank
    FROM RecursiveTagCounts r
    WHERE r.Count > 1000
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        count(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        count(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        count(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        count(DISTINCT b.Id) AS TotalBadges,
        max(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostActivityRank AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        COALESCE(p.Score, 0) AS Score,
        COALESCE(p.ViewCount, 0) AS Views,
        p.Tags,
        rank() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentRank,
        row_number() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY COALESCE(p.Score,0) DESC, COALESCE(p.ViewCount,0) DESC) AS ScoreRank,
        sum(COALESCE(p.Score,0)) OVER (PARTITION BY p.OwnerUserId) AS TotalUserScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserRecentPosts AS (
    SELECT par.OwnerUserId, par.Id AS PostId, par.PostTypeId, par.CreationDate, par.Score, par.Views, par.Tags
    FROM PostActivityRank par
    WHERE par.RecentRank <= 5
),
DuplicatesWithDetails AS (
    SELECT
        pl.PostId AS DuplicatePostId,
        pl.RelatedPostId AS OriginalPostId,
        p1.Title AS DuplicateTitle,
        p2.Title AS OriginalTitle,
        pl.CreationDate AS LinkCreationDate
    FROM PostLinks pl
    INNER JOIN Posts p1 ON p1.Id = pl.PostId
    INNER JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3
),
TopDuplicateUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        count(DISTINCT dup.DuplicatePostId) AS DupPostsCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN DuplicatesWithDetails dup ON dup.DuplicatePostId = p.Id
    GROUP BY u.Id, u.DisplayName
    HAVING count(DISTINCT dup.DuplicatePostId) > 2
),
UserScoreWindow AS (
    SELECT
        u.Id AS Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        sum(COALESCE(p.Score,0)) AS TotalPostScore,
        rank() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        dense_rank() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRepRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.TotalPostScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    CASE
        WHEN ub.GoldBadges > 10 THEN 'Elite'
        WHEN ub.SilverBadges > 20 THEN 'Experienced'
        WHEN ub.BronzeBadges > 50 THEN 'Contributor'
        ELSE 'Novice'
    END AS UserLevel,
    t.Tags AS RecentTopTags,
    dt.DupPostsCount AS DuplicatePostsByUser,
    (
        SELECT count(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
          AND ph.UserId = u.Id
    ) AS ClosedPostsCount,
    (
        SELECT p.Title || ' [' || COALESCE(p.Tags, 'no-tags') || ']'
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
        ORDER BY COALESCE(p.Score,0) DESC, p.CreationDate DESC
        LIMIT 1
    ) AS TopScoredPostTitle,
    urp.RecentRank,
    urp.PostTypeId AS RecentPostTypeId,
    urp.Score AS RecentPostScore,
    urp.Views AS RecentPostViews,
    (
      -- count non-empty tags from tag string like "<tag1><tag2>"
      SELECT count(*) FROM (
        SELECT trim(tag) AS tag
        FROM (
          SELECT
            CASE
              WHEN urp.Tags IS NULL OR urp.Tags = '' THEN NULL
              ELSE regexp_split_to_table(
                substr(urp.Tags, 2, greatest(length(urp.Tags) - 2, 0)),
                '><'
              )
            END AS tag
        ) x
        WHERE tag IS NOT NULL AND tag <> ''
      ) y
    ) AS RecentPostTagCount
FROM UserScoreWindow u
LEFT JOIN UserBadgeSummary ub ON ub.UserId = u.Id
LEFT JOIN TopDuplicateUsers dt ON dt.Id = u.Id
LEFT JOIN LATERAL (
    SELECT par.RecentRank, par.PostTypeId, par.Score, par.Views, par.Tags, par.Id, par.CreationDate
    FROM PostActivityRank par
    WHERE par.OwnerUserId = u.Id
    ORDER BY par.CreationDate DESC
    LIMIT 1
) urp ON TRUE
LEFT JOIN (
    SELECT
        Id AS PostId,
        array_agg(DISTINCT tag) AS Tags
    FROM (
        SELECT
            p.Id,
            regexp_split_to_table(
              substr(p.Tags, 2, greatest(length(p.Tags) - 2, 0)),
              '><'
            ) AS tag
        FROM Posts p
        WHERE p.Tags IS NOT NULL AND p.Tags <> ''
    ) s
    GROUP BY Id
) t ON t.PostId = urp.Id
WHERE u.Reputation > 1000
ORDER BY u.Reputation DESC
LIMIT 100;