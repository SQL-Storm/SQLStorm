-- {"query": "1178.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3201}
WITH UserAccountMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS AccountCreationDate,
        DATE_PART('day', CAST('2024-10-01' AS date) - u.CreationDate) AS AccountAgeDays,
        u.Views AS ProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadgesCount,
        NTILE(10) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationDecile,
        CASE
            WHEN u.Reputation >= 100000 THEN 'Legendary Contributor'
            WHEN u.Reputation >= 25000 THEN 'Highly Esteemed'
            WHEN u.Reputation >= 5000 THEN 'Established Expert'
            WHEN u.Reputation >= 1000 THEN 'Active Participant'
            ELSE 'Newcomer'
        END AS ReputationTierName,
        MAX(u.LastAccessDate) AS LastAccessed
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
PostEngagementSummary AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount AS QuestionAnswerCount,
        p.FavoriteCount AS QuestionFavoriteCount,
        COALESCE(LENGTH(p.Body), 0) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        REPLACE(LOWER(TRIM(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2))), '><', ',') AS CleanedTags,
        AVG(c.Score) AS AverageCommentScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsOnPost,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        NULLIF(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        (
            SELECT AVG(ans.Score)
            FROM Posts ans
            WHERE ans.ParentId = p.Id
              AND ans.PostTypeId = 2
              AND ans.OwnerUserId = p.OwnerUserId
        ) AS AvgSelfAnswerScoreOnQuestion,
        RANK() OVER (PARTITION BY p.PostTypeId, DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS PostMonthlyRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Body, p.Title, p.Tags, p.AcceptedAnswerId
),
UserHistoricalActions AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS TotalEditsMade,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 101) THEN ph.Id END) AS TotalCloseVotesCast,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (11) THEN ph.Id END) AS TotalReopenVotesCast,
        MAX(ph.CreationDate) AS LatestHistoryActivity,
        LAG(MAX(ph.CreationDate)) OVER (PARTITION BY ph.UserId ORDER BY MAX(ph.CreationDate)) AS PreviousHistoryActivityDate,
        (
            SELECT COUNT(DISTINCT v_sub.Id)
            FROM Votes v_sub
            WHERE v_sub.UserId = ph.UserId AND v_sub.VoteTypeId = 8
        ) AS BountiesStarted,
        (
            SELECT COUNT(DISTINCT pl.Id)
            FROM PostLinks pl
            WHERE pl.RelatedPostId IN (SELECT p_sub.Id FROM Posts p_sub WHERE p_sub.OwnerUserId = ph.UserId)
            AND pl.LinkTypeId = 3
        ) AS LinkedAsDuplicatesCount
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TopQuestionTags AS (
    SELECT
        tag_name,
        COUNT(PostId) AS TaggedQuestionCount,
        SUM(PostScore) AS TotalTagScore
    FROM (
        SELECT
            pe.PostId,
            pe.PostScore,
            UNNEST(STRING_TO_ARRAY(SUBSTRING(pe.CleanedTags FROM 1 FOR LENGTH(pe.CleanedTags)), ',')) AS tag_name
        FROM PostEngagementSummary pe
        WHERE pe.PostTypeId = 1 AND pe.PostScore > 50 AND pe.QuestionAnswerCount > 5
    ) AS TaggedPosts
    WHERE tag_name IS NOT NULL AND tag_name <> ''
    GROUP BY tag_name
    ORDER BY TotalTagScore DESC, TaggedQuestionCount DESC
    LIMIT 10
),
UsersWithCommentsButNoPosts AS (
    SELECT DISTINCT c.UserId
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    EXCEPT
    SELECT DISTINCT p.OwnerUserId
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT
    uam.UserId,
    uam.DisplayName,
    uam.Reputation,
    uam.ReputationTierName,
    uam.GoldBadgesCount,
    uam.SilverBadgesCount,
    uam.BronzeBadgesCount,
    uam.AccountAgeDays,
    uam.ProfileViews,
    uam.TotalUpVotesGiven,
    uam.TotalDownVotesGiven,
    SUM(CASE WHEN pes.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwnedCount,
    SUM(CASE WHEN pes.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwnedCount,
    SUM(pes.PostScore) AS TotalPostsScore,
    SUM(pes.PostViewCount) AS TotalPostsViewCount,
    AVG(pes.AverageCommentScore) AS OverallAvgCommentScore,
    SUM(pes.TotalCommentsOnPost) AS TotalCommentsReceivedOnPosts,
    MAX(pes.LastCommentDate) AS LatestCommentReceived,
    AVG(pes.AvgSelfAnswerScoreOnQuestion) AS AvgSelfAnswerScoreAcrossOwnQuestions,
    COALESCE(SUM(pes.UpVotesReceived), 0) AS TotalUpVotesReceivedOnPosts,
    COALESCE(SUM(pes.DownVotesReceived), 0) AS TotalDownVotesReceivedOnPosts,
    SUM(CASE WHEN pes.HasAcceptedAnswer THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
    COALESCE(ROUND(CAST(SUM(CASE WHEN pes.HasAcceptedAnswer THEN 1 ELSE 0 END) AS NUMERIC) * 100 / NULLIF(SUM(CASE WHEN pes.PostTypeId = 1 THEN 1 ELSE 0 END), 0), 2), 0) AS QuestionAcceptanceRate,
    MAX(uha.TotalEditsMade) AS UserTotalEditsMade,
    MAX(uha.TotalCloseVotesCast) AS UserTotalCloseVotesCast,
    MAX(uha.LatestHistoryActivity) AS UserLatestHistoricalAction,
    (
        SELECT COUNT(DISTINCT tqa.tag_name)
        FROM TopQuestionTags tqa
        WHERE tqa.tag_name IN (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))
            FROM Posts p
            WHERE p.OwnerUserId = uam.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
        )
    ) AS PopularTagsUsedCount,
    (
        SELECT COUNT(DISTINCT v_sub.Id)
        FROM Votes v_sub
        WHERE v_sub.UserId = uam.UserId AND v_sub.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year')
        AND v_sub.VoteTypeId IN (2,3)
    ) AS RecentVotesByThisUser,
    MAX(CASE WHEN uam.UserId IN (SELECT UserId FROM UsersWithCommentsButNoPosts) THEN 1 ELSE 0 END) AS IsCommenterOnly,
    LAG(uam.Reputation) OVER (ORDER BY uam.Reputation DESC) AS PrevHigherReputationUserReputation,
    LEAD(uam.Reputation) OVER (ORDER BY uam.Reputation DESC) AS NextLowerReputationUserReputation
FROM UserAccountMetrics uam
LEFT JOIN PostEngagementSummary pes ON uam.UserId = pes.OwnerUserId
LEFT JOIN UserHistoricalActions uha ON uam.UserId = uha.UserId
WHERE
    uam.Reputation >= 1000
    AND uam.GoldBadgesCount > 0
    AND uam.AccountAgeDays > 365
    AND uam.DisplayName IS NOT NULL AND uam.DisplayName <> ''
    AND (uam.DisplayName LIKE 'A%' OR uam.DisplayName LIKE 'S%')
    AND EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = uam.UserId AND PostTypeId = 1 AND Score > 100)
    AND (pes.PostMonthlyRank <= 5 OR pes.PostMonthlyRank IS NULL)
GROUP BY
    uam.UserId, uam.DisplayName, uam.Reputation, uam.ReputationTierName,
    uam.GoldBadgesCount, uam.SilverBadgesCount, uam.BronzeBadgesCount,
    uam.AccountAgeDays, uam.ProfileViews, uam.TotalUpVotesGiven, uam.TotalDownVotesGiven,
    uam.ReputationDecile, uam.LastAccessed
HAVING
    COUNT(DISTINCT pes.PostId) > 10
    AND SUM(CASE WHEN pes.PostTypeId = 1 THEN 1 ELSE 0 END) >= 2
    AND COALESCE(SUM(pes.UpVotesReceived), 0) > 50
    AND COALESCE(AVG(pes.AverageCommentScore), 0) > 0.5
ORDER BY
    uam.Reputation DESC, QuestionsOwnedCount DESC, TotalUpVotesReceivedOnPosts DESC
LIMIT 50;