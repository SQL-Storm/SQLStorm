WITH UserPosts AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(*) AS TotalPosts, 
        AVG(Score) AS AvgPostScore,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        -- Use standard SQL string aggregation without DISTINCT+ORDER in aggregate clause for broad compatibility.
        -- Build unique tags via subquery to avoid DISTINCT in STRING_AGG's ORDER BY which some engines disallow.
        (
            SELECT STRING_AGG(tag, ',')
            FROM (
                SELECT DISTINCT SUBSTRING(Tags FROM 2 FOR (CHAR_LENGTH(Tags) - 2)) AS tag
                FROM Posts p2
                WHERE p2.OwnerUserId = Posts.OwnerUserId
                AND Tags IS NOT NULL
            ) t
        ) AS UniqueTags
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
), UserVotes AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalVotesCast,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM Votes 
    WHERE UserId IS NOT NULL
    GROUP BY UserId
), UserBadges AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN "class" = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN "class" = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN "class" = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges 
    GROUP BY UserId
), PostClosures AS (
    SELECT 
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11)
    GROUP BY ph.PostId
    HAVING MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) = 1
       AND MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) = 1
), UserComments AS (
    SELECT UserId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(p.TotalPosts, 0) + COALESCE(c.CommentCount, 0) AS TotalContributions,
    p.QuestionsAsked,
    p.AnswersProvided,
    p.AvgPostScore,
    (p.AvgPostScore / NULLIF((SELECT AVG(Score) FROM Posts WHERE Score > 0), 0)) AS ScoreRatio,
    v.TotalVotesCast,
    ROUND(CASE WHEN v.TotalVotesCast IS NULL OR v.TotalVotesCast = 0 THEN NULL ELSE v.UpvotesGiven * 100.0 / v.TotalVotesCast END, 2) AS UpvotePercentage,
    b.TotalBadges,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    (SELECT COUNT(DISTINCT RelatedPostId) 
     FROM PostLinks pl 
     WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
       AND LinkTypeId = 3
    ) AS DuplicateMarkings,
    (SELECT COUNT(*) FROM PostClosures pc WHERE pc.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) AS ClosedReopenedPosts,
    p.UniqueTags,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    CASE 
        WHEN u.Reputation >= 100000 THEN 'Legendary' 
        WHEN u.Reputation >= 50000 THEN 'Epic' 
        WHEN u.Reputation >= 10000 THEN 'Veteran' 
        ELSE 'Regular' 
    END AS ReputationClass
FROM Users u
LEFT JOIN UserPosts p ON u.Id = p.UserId
LEFT JOIN UserVotes v ON u.Id = v.UserId
LEFT JOIN UserBadges b ON u.Id = b.UserId
LEFT JOIN UserComments c ON u.Id = c.UserId
WHERE (u.Reputation > 1000)
    OR (COALESCE(p.TotalPosts, 0) > 50)
    OR (COALESCE(v.TotalVotesCast, 0) > 200)
    OR (COALESCE(b.TotalBadges, 0) > 10)
ORDER BY COALESCE(p.TotalPosts, 0) + COALESCE(c.CommentCount, 0) DESC, u.Reputation DESC
FETCH FIRST 100 ROWS ONLY;