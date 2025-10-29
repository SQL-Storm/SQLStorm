-- {"query": "3906.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1820} 

/*  Comprehensive benchmark query for the StackOverflow data model  */
WITH
/*--------------------------------------------------------------
  Recent activity (last 90 days) – posts, comments, votes, badges
--------------------------------------------------------------*/
recent_posts AS (
    SELECT
        p.Id            AS PostId,
        p.OwnerUserId   AS OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Tags, '') AS TagsRaw,
        CASE 
            WHEN p.Tags IS NULL THEN 0
            ELSE (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', ''))) / 2 + 1
        END                AS TagCount
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
),

recent_comments AS (
    SELECT
        c.PostId,
        COUNT(*) FILTER (WHERE c.Score > 0) AS PositiveComments,
        COUNT(*) FILTER (WHERE c.Score <= 0) AS NonPositiveComments,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY c.PostId
),

recent_votes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5)           AS Favorites,
        MAX(v.CreationDate)                               AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY v.PostId
),

recent_badges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date)                         AS LastBadgeDate
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY b.UserId
),

/*--------------------------------------------------------------
  User‑level statistics derived from the recent activity CTEs
--------------------------------------------------------------*/
user_stats AS (
    SELECT
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(rp.PostCount, 0)         AS RecentPostCount,
        COALESCE(rc.PositiveComments,0)  + COALESCE(rc.NonPositiveComments,0) AS RecentCommentCount,
        COALESCE(rv.UpVotes,0)            AS RecentUpVotes,
        COALESCE(rv.DownVotes,0)          AS RecentDownVotes,
        COALESCE(rb.GoldBadges,0)         AS RecentGoldBadges,
        COALESCE(rb.SilverBadges,0)       AS RecentSilverBadges,
        COALESCE(rb.BronzeBadges,0)       AS RecentBronzeBadges,
        GREATEST(
            COALESCE(rp.LastPostDate,'epoch'::timestamp),
            COALESCE(rc.LastCommentDate,'epoch'::timestamp),
            COALESCE(rv.LastVoteDate,'epoch'::timestamp),
            COALESCE(rb.LastBadgeDate,'epoch'::timestamp)
        )                                 AS LastActivityDate
    FROM Users u
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*)                         AS PostCount,
            MAX(CreationDate)                AS LastPostDate
        FROM recent_posts
        GROUP BY OwnerUserId
    ) rp ON rp.OwnerUserId = u.Id
    LEFT JOIN recent_comments rc ON rc.PostId = ANY (
        SELECT PostId FROM recent_posts WHERE OwnerUserId = u.Id
    )
    LEFT JOIN recent_votes rv ON rv.PostId = ANY (
        SELECT PostId FROM recent_posts WHERE OwnerUserId = u.Id
    )
    LEFT JOIN recent_badges rb ON rb.UserId = u.Id
),

/*--------------------------------------------------------------
  Tag popularity based on recent posts (derived from Tags field)
--------------------------------------------------------------*/
tag_popularity AS (
    SELECT
        TRIM(BOTH '><' FROM UNNEST(STRING_TO_ARRAY(p.TagsRaw, '><'))) AS Tag,
        COUNT(*)                                                   AS RecentUseCount
    FROM recent_posts p
    WHERE p.TagsRaw <> ''
    GROUP BY Tag
),

/*--------------------------------------------------------------
  Top 10 tags by recent usage, with ranking via window function
--------------------------------------------------------------*/
top_tags AS (
    SELECT
        Tag,
        RecentUseCount,
        ROW_NUMBER() OVER (ORDER BY RecentUseCount DESC) AS TagRank
    FROM tag_popularity
    ORDER BY RecentUseCount DESC
    LIMIT 10
),

/*--------------------------------------------------------------
  Users with at least one gold badge OR at least 5 recent posts
  – union both sets to test set operators and duplicate elimination
--------------------------------------------------------------*/
gold_or_active_users AS (
    SELECT UserId FROM recent_badges WHERE GoldBadges > 0
    UNION
    SELECT OwnerUserId FROM recent_posts GROUP BY OwnerUserId HAVING COUNT(*) >= 5
),

/*--------------------------------------------------------------
  Correlated subquery to fetch the most recent post title per user
--------------------------------------------------------------*/
user_latest_title AS (
    SELECT
        u.Id AS UserId,
        (SELECT p.Title
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
           AND p.CreationDate = (
               SELECT MAX(CreationDate) FROM Posts WHERE OwnerUserId = u.Id
           )
         LIMIT 1) AS LatestTitle
    FROM Users u
),

/*--------------------------------------------------------------
  Final result set combining all pieces
--------------------------------------------------------------*/
final_report AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.RecentPostCount,
        us.RecentCommentCount,
        us.RecentUpVotes,
        us.RecentDownVotes,
        us.RecentGoldBadges,
        us.RecentSilverBadges,
        us.RecentBronzeBadges,
        us.LastActivityDate,
        ul.LatestTitle,
        CASE
            WHEN us.RecentGoldBadges > 0 THEN 'Gold'
            WHEN us.RecentSilverBadges > 0 THEN 'Silver'
            WHEN us.RecentBronzeBadges > 0 THEN 'Bronze'
            ELSE 'None'
        END AS HighestBadgeClass,
        COALESCE(
            (SELECT STRING_AGG(t.Tag, ', ')
             FROM top_tags t
             WHERE t.TagRank <= 3), 
            '(no top tags)'
        ) AS TopThreeTags
    FROM user_stats us
    INNER JOIN gold_or_active_users gau ON gau.UserId = us.UserId
    LEFT JOIN user_latest_title ul ON ul.UserId = us.UserId
    WHERE us.LastActivityDate >= CURRENT_DATE - INTERVAL '30 days'
)

SELECT
    fr.*,
    /* Additional derived column: activity score */
    (fr.RecentPostCount * 4
     + fr.RecentCommentCount * 2
     + fr.RecentUpVotes * 3
     - fr.RecentDownVotes
     + fr.RecentGoldBadges * 10
     + fr.RecentSilverBadges * 5
     + fr.RecentBronzeBadges * 2) AS ActivityScore
FROM final_report fr
ORDER BY ActivityScore DESC, fr.Reputation DESC
LIMIT 100;
