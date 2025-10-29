-- {"query": "3967.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2129} 

WITH 
-- Aggregate user reputation, location and badge counts
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '[unknown]')               AS Location,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)          AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)          AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)          AS BronzeBadges,
        COUNT(p.Id)                                     AS TotalPosts,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
        MAX(p.CreationDate)                             AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),

-- Most recent vote and comment dates per user
RecentActivity AS (
    SELECT 
        u.Id,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Votes    v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),

-- Concatenate distinct tags a user has ever used in questions
TagAggregates AS (
    SELECT 
        p.OwnerUserId AS UserId,
        STRING_AGG(DISTINCT t.TagName, ',') AS TagsUsed
    FROM Posts p
    JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS tag_raw(tag) ON TRUE
    JOIN Tags t ON t.TagName = tag_raw.tag
    WHERE p.PostTypeId = 1                         -- only questions
    GROUP BY p.OwnerUserId
),

-- Rank users by reputation (only those above a threshold)
TopUsers AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.TotalPosts,
        us.AvgScore,
        us.LastPostDate,
        ra.LastVoteDate,
        ra.LastCommentDate,
        COALESCE(ta.TagsUsed, '')                     AS TagsUsed,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalPosts DESC) AS RankByRep
    FROM UserStats us
    LEFT JOIN RecentActivity ra ON ra.Id = us.Id
    LEFT JOIN TagAggregates ta  ON ta.UserId = us.Id
    WHERE us.Reputation > 1000
),

-- Details on closed/duplicate questions
ClosedDuplicatePosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        ph.Comment::int                                   AS CloseReasonId,
        ph.Text::jsonb ->> 'OriginalQuestionIds'          AS DuplicatesJson,
        pl.RelatedPostId                                  AS DuplicateOf
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10   -- closed
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3       -- duplicate link
    WHERE p.ClosedDate IS NOT NULL
),

-- Combine top users with their latest post (or closed duplicate info)
Combined AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.RankByRep,
        u.TagsUsed,
        CASE 
            WHEN cd.Id IS NOT NULL THEN 'Closed/Duplicate' 
            ELSE 'Active' 
        END                                              AS Status,
        COALESCE(cd.Title, p.Title)                     AS RepresentativeTitle,
        COALESCE(cd.DuplicateOf, p.Id)                  AS RepresentativePostId,
        COALESCE(cd.CloseReasonId, 0)                  AS CloseReason,
        COALESCE(cd.DuplicatesJson, '[]')               AS DuplicateSet
    FROM TopUsers u
    LEFT JOIN ClosedDuplicatePosts cd ON cd.Id = (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate = (
        SELECT MAX(p3.CreationDate)
        FROM Posts p3
        WHERE p3.OwnerUserId = u.Id
    )
)

SELECT *
FROM Combined
WHERE RankByRep <= 100
ORDER BY RankByRep;
