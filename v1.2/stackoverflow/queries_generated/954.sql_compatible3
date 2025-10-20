WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count,
        1 AS Level,
        ARRAY[t.Id] AS Path,
        t.WikiPostId
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE

    UNION ALL

    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        rh.Level + 1,
        rh.Path || t2.Id,
        t2.WikiPostId
    FROM RecursiveTagHierarchy rh
    JOIN Posts p ON p.Id = rh.WikiPostId
    JOIN Tags t2 ON t2.WikiPostId = p.Id
    WHERE NOT (t2.Id = ANY(rh.Path)) AND rh.Level < 3
), LatestVotesPerPost AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        v.Id,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC, v.Id DESC) AS rn
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
), UserScoreStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        SUM(COALESCE(lv_up.cnt,0)) AS UpVotesReceived,
        SUM(COALESCE(lv_down.cnt,0)) AS DownVotesReceived,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        LEAD(u.LastAccessDate) OVER (ORDER BY u.LastAccessDate) - u.LastAccessDate AS NextAccessGap,
        LAG(u.LastAccessDate) OVER (ORDER BY u.LastAccessDate) - u.LastAccessDate AS PrevAccessGap
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT 
            v.PostId,
            COUNT(*) AS cnt
        FROM Votes v
        WHERE v.VoteTypeId = 2
        GROUP BY v.PostId
    ) lv_up ON lv_up.PostId = p.Id
    LEFT JOIN (
        SELECT 
            v.PostId,
            COUNT(*) AS cnt
        FROM Votes v
        WHERE v.VoteTypeId = 3
        GROUP BY v.PostId
    ) lv_down ON lv_down.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
), QuestionsWithDuplicates AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        dup.RelatedPostId AS DuplicateOfQuestionId,
        dup.CreationDate AS DuplicateLinkDate
    FROM Posts p
    LEFT JOIN PostLinks dup ON dup.PostId = p.Id AND dup.LinkTypeId = 3
    WHERE p.PostTypeId = 1
), UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT c.PostId) AS UniquePostsCommented
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
), PostActivityWindows AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.LastActivityDate,
        LEAD(p.CreationDate) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostCreation,
        LAG(p.LastActivityDate) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PrevPostLastActivity,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/3600 AS ActiveHours
    FROM Posts p
), ComplexUserPerformance AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.TotalPosts,
        us.TotalPostScore,
        us.AvgQuestionScore,
        us.AvgAnswerScore,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.UpVotesReceived,
        us.DownVotesReceived,
        us.ReputationRank,
        COALESCE(ucs.TotalComments,0) AS TotalComments,
        COALESCE(ucs.AvgCommentLength,0) AS AvgCommentLength,
        COALESCE(ucs.UniquePostsCommented,0) AS UniquePostsCommented,
        (
            SELECT COUNT(*)
            FROM Posts p2
            WHERE p2.AcceptedAnswerId IN (
                SELECT p3.Id FROM Posts p3 WHERE p3.OwnerUserId = us.UserId AND p3.PostTypeId = 2
            )
        ) AS AcceptedAnswersCount,
        CASE WHEN EXISTS (
            SELECT 1 FROM PostHistory ph
            JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId AND pht.Name LIKE '%Closed%'
            WHERE ph.PostId IN (SELECT p4.Id FROM Posts p4 WHERE p4.OwnerUserId = us.UserId)
        ) THEN 1 ELSE 0 END AS HasPostClosedHistory,
        (
            SELECT STRING_AGG(b2.Name, '|') 
            FROM Badges b2 
            WHERE b2.UserId = us.UserId AND b2.Class = 3
        ) AS BronzeBadgeNames,
        (
            (us.TotalPostScore * 1.5) + (us.UpVotesReceived * 2) - (us.DownVotesReceived * 1.2) + 
            (us.GoldBadges * 10) + (us.SilverBadges * 5) + (us.BronzeBadges * 2) + 
            (COALESCE(ucs.TotalComments,0) * 0.5)
        ) AS ActivityScore,
        us.UserId AS uid_for_grouping
    FROM UserScoreStats us
    LEFT JOIN UserCommentStats ucs ON ucs.UserId = us.UserId
)
SELECT 
    cup.DisplayName,
    cup.TotalPosts,
    cup.TotalPostScore,
    cup.AvgQuestionScore,
    cup.AvgAnswerScore,
    cup.GoldBadges,
    cup.SilverBadges,
    cup.BronzeBadges,
    cup.UpVotesReceived,
    cup.DownVotesReceived,
    cup.ReputationRank,
    cup.TotalComments,
    cup.AvgCommentLength,
    cup.UniquePostsCommented,
    cup.AcceptedAnswersCount,
    cup.HasPostClosedHistory,
    COALESCE(cup.BronzeBadgeNames, 'None') AS BronzeBadgeNames,
    ROUND(cup.ActivityScore,2) AS ActivityScore,
    RANK() OVER (ORDER BY cup.ActivityScore DESC) AS ActivityRank,
    (
        SELECT COUNT(DISTINCT tag)
        FROM (
            SELECT UNNEST(STRING_TO_ARRAY(REGEXP_REPLACE(COALESCE(p.Tags,'<undefined>'), '[<>]', ' ', 'g'), ' ')) AS tag
            FROM Posts p
            WHERE p.OwnerUserId = cup.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
        ) t_un
    ) AS DistinctQuestionTagsCount,
    CASE WHEN cup.UserId IN (
        SELECT UserId FROM UserScoreStats
        WHERE TotalPostScore > (
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TotalPostScore) FROM UserScoreStats
        )
        AND GoldBadges > 0
    ) THEN 1 ELSE 0 END AS AboveMedianGoldBadgeUser,
    cup.UserId
FROM ComplexUserPerformance cup
ORDER BY cup.ActivityScore DESC
LIMIT 25;