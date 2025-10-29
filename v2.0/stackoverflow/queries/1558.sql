-- {"query": "1558.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3381}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        EXTRACT(DAY FROM AGE(TIMESTAMP '2024-10-01 12:34:56', u.CreationDate)) AS UserAgeDays,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserTotalUpVotesReceived,
        u.DownVotes AS UserTotalDownVotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COALESCE(AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 WHEN v.VoteTypeId = 3 THEN -1.0 ELSE 0.0 END), 0.0) AS AvgVoteImpactByMe,
        NTILE(5) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationQuintile,
        RANK() OVER (ORDER BY u.Views DESC, u.Reputation DESC) AS UserViewRank
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE
        u.Reputation > 750
        AND u.LastAccessDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '9 months'
        AND u.Location IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostActivityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.Title,
        p.Tags,
        p.LastActivityDate,
        EXTRACT(HOUR FROM AGE(TIMESTAMP '2024-10-01 12:34:56', p.LastActivityDate)) AS LastActivityAgoHours,
        p.ClosedDate,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Body,
        (SELECT COUNT(DISTINCT ph_sub.UserId)
         FROM PostHistory ph_sub
         WHERE ph_sub.PostId = p.Id
           AND ph_sub.PostHistoryTypeId IN (4, 5, 6)
        ) AS UniqueEditorsCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditHistoryEvents,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        COUNT(c.Id) AS TotalCommentsOnPost,
        STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><') AS TagArray,
        CASE
            WHEN p.Score > 200 AND p.ViewCount > 50000 THEN 'Mega_Popular'
            WHEN p.Score BETWEEN 50 AND 200 AND p.ViewCount BETWEEN 5000 AND 50000 THEN 'Highly_Engaged'
            WHEN p.Score BETWEEN 10 AND 49 AND p.ViewCount BETWEEN 500 AND 4999 THEN 'Active'
            ELSE 'Moderate_Engagement'
        END AS PostEngagementTier,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedFromPosts,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateOfPosts
    FROM
        Posts p
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostLinks pl ON p.Id = pl.PostId
    WHERE
        p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 year'
        AND p.PostTypeId IN (1, 2)
        AND p.Score >= 5
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, p.LastActivityDate,
        p.ClosedDate, p.AcceptedAnswerId, p.ParentId, p.Body
),
RankedActivity AS (
    SELECT
        pam.PostId,
        pam.PostTypeId,
        pam.PostTypeName,
        pam.OwnerUserId,
        pam.PostCreationDate,
        pam.Score,
        pam.ViewCount,
        pam.AnswerCount,
        pam.CommentCount,
        pam.FavoriteCount,
        pam.Title,
        pam.Tags,
        pam.LastActivityDate,
        pam.LastActivityAgoHours,
        pam.ClosedDate,
        pam.AcceptedAnswerId,
        pam.ParentId,
        pam.Body,
        pam.UniqueEditorsCount,
        pam.CloseEvents,
        pam.ReopenEvents,
        pam.TotalEditHistoryEvents,
        pam.AvgCommentScore,
        pam.TotalCommentsOnPost,
        pam.TagArray,
        pam.PostEngagementTier,
        pam.LinkedFromPosts,
        pam.DuplicateOfPosts,
        ROW_NUMBER() OVER (PARTITION BY pam.OwnerUserId ORDER BY pam.Score DESC, pam.LastActivityDate DESC) AS UserPostRank,
        RANK() OVER (ORDER BY pam.Score DESC, pam.ViewCount DESC, pam.FavoriteCount DESC) AS OverallPostRank,
        AVG(pam.Score) OVER (PARTITION BY DATE_TRUNC('month', pam.PostCreationDate)) AS MonthlyAvgPostScore,
        SUM(CASE WHEN pam.PostTypeId = 1 THEN pam.Score ELSE 0 END) OVER (PARTITION BY pam.OwnerUserId) AS OwnerQuestionScoreSum,
        SUM(CASE WHEN pam.PostTypeId = 2 THEN pam.Score ELSE 0 END) OVER (PARTITION BY pam.OwnerUserId) AS OwnerAnswerScoreSum,
        COUNT(pam.PostId) OVER (PARTITION BY pam.OwnerUserId) AS OwnerTotalPostsContribution,
        (pam.Score * 0.7 + pam.ViewCount * 0.05 + pam.CommentCount * 0.15 + pam.FavoriteCount * 0.1) AS WeightedEngagementScore,
        FIRST_VALUE(pam.Title) OVER (PARTITION BY pam.OwnerUserId ORDER BY pam.Score DESC) AS TopScoringPostTitleByOwner
    FROM
        PostActivityMetrics pam
),
ComplexUserPostInteraction AS (
    SELECT
        ue.UserId,
        ue.DisplayName AS UserDisplayName,
        ue.Reputation,
        ue.GoldBadges,
        ue.UserAgeDays,
        ue.ReputationQuintile,
        ra.PostId,
        ra.PostTypeName,
        ra.Title AS PostTitle,
        ra.Score AS PostScore,
        ra.ViewCount AS PostViewCount,
        ra.FavoriteCount AS PostFavoriteCount,
        ra.PostEngagementTier,
        ra.UniqueEditorsCount,
        ra.CloseEvents,
        ra.ReopenEvents,
        ra.AvgCommentScore,
        ra.TotalCommentsOnPost,
        ra.LastActivityAgoHours,
        ra.WeightedEngagementScore,
        ra.OverallPostRank,
        (ra.OwnerQuestionScoreSum + ra.OwnerAnswerScoreSum) AS OwnerTotalContentScore,
        (SELECT COUNT(DISTINCT c_sub.UserId) FROM Comments c_sub WHERE c_sub.PostId = ra.PostId AND c_sub.UserId IS NOT NULL AND c_sub.UserId != ue.UserId) AS OtherCommentersCount,
        COALESCE(
            NULLIF(
                REPLACE(
                    SUBSTRING(ra.Body FROM POSITION('<p>' IN ra.Body) + 3 FOR CHAR_LENGTH(ra.Body) - POSITION('<p>' IN ra.Body) - 3),
                    '&amp;', '&'
                ),
                ''
            ),
            'No valid HTML paragraph found in body'
        ) AS CleanedInitialBodySnippet,
        ra.AcceptedAnswerId,
        ra.ParentId,
        ra.ClosedDate,
        ra.Title,
        ra.Body,
        ra.TagArray,
        ra.PostTypeId
    FROM
        UserEngagement ue
    INNER JOIN
        RankedActivity ra ON ue.UserId = ra.OwnerUserId
    WHERE
        ra.UserPostRank <= 3
        AND ra.OverallPostRank <= 2000
        AND (ue.ReputationQuintile = 1 OR ue.GoldBadges >= 1)
        AND ra.LastActivityAgoHours < 1440
        AND NOT (ra.PostTypeId = 1 AND ra.ClosedDate IS NOT NULL AND ra.CloseEvents = 1 AND ra.ReopenEvents = 0)
        AND (ra.Title ILIKE '%sql%' OR ra.Body ILIKE '%database%' OR ra.Title ILIKE '%performance%' OR ra.Body ILIKE '%optimization%')
        AND (
                'sql' = ANY(ra.TagArray)
                OR 'database' = ANY(ra.TagArray)
                OR 'postgresql' = ANY(ra.TagArray)
                OR 'mysql' = ANY(ra.TagArray)
                OR 'performance' = ANY(ra.TagArray)
            )
        AND ra.AvgCommentScore > (
            SELECT AVG(c2.Score)
            FROM Comments c2
            JOIN Posts p2 ON c2.PostId = p2.Id
            WHERE p2.PostTypeId = ra.PostTypeId
              AND p2.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
        )
        AND ue.UserId IN (SELECT DISTINCT v_sub.UserId FROM Votes v_sub WHERE v_sub.PostId = ra.PostId AND v_sub.VoteTypeId = 5)
)
SELECT
    'Top_Question_Engager_Analysis' AS AnalysisCategory,
    cu.UserDisplayName,
    cu.Reputation,
    cu.GoldBadges,
    cu.PostTitle,
    cu.PostTypeName,
    cu.PostScore,
    cu.PostViewCount,
    cu.PostFavoriteCount,
    cu.AvgCommentScore,
    cu.LastActivityAgoHours,
    cu.WeightedEngagementScore,
    cu.UniqueEditorsCount,
    cu.CloseEvents,
    cu.ReopenEvents,
    cu.CleanedInitialBodySnippet,
    cu.OtherCommentersCount
FROM
    ComplexUserPostInteraction cu
WHERE
    cu.PostTypeName = 'Question'
    AND cu.WeightedEngagementScore >= 150
    AND cu.PostId NOT IN (SELECT pl_sub.RelatedPostId FROM PostLinks pl_sub WHERE pl_sub.PostId = cu.PostId AND pl_sub.LinkTypeId = 3)
    AND cu.GoldBadges > 0
    AND cu.OtherCommentersCount > 2
    AND cu.UserAgeDays > 730
    AND cu.ReopenEvents > 0
    AND cu.PostViewCount > cu.PostScore * 100
    AND LEFT(cu.PostTitle, 1) = UPPER(LEFT(cu.PostTitle, 1))
UNION ALL
SELECT
    'Top_Answer_Contributor_Analysis' AS AnalysisCategory,
    cu.UserDisplayName,
    cu.Reputation,
    cu.GoldBadges,
    cu.PostTitle,
    cu.PostTypeName,
    cu.PostScore,
    cu.PostViewCount,
    cu.PostFavoriteCount,
    cu.AvgCommentScore,
    cu.LastActivityAgoHours,
    cu.WeightedEngagementScore,
    cu.UniqueEditorsCount,
    cu.CloseEvents,
    cu.ReopenEvents,
    cu.CleanedInitialBodySnippet,
    cu.OtherCommentersCount
FROM
    ComplexUserPostInteraction cu
WHERE
    cu.PostTypeName = 'Answer'
    AND cu.PostScore >= 75
    AND cu.AcceptedAnswerId IS NOT NULL AND cu.AcceptedAnswerId = cu.PostId
    AND cu.UniqueEditorsCount >= 2
    AND cu.UserAgeDays > 1095
    AND (
            SELECT SUM(p_q.Score)
            FROM Posts p_q
            WHERE p_q.Id = cu.ParentId AND p_q.PostTypeId = 1 AND p_q.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 year'
        ) > 150
    AND EXISTS (
            SELECT 1
            FROM Comments c_ans
            WHERE c_ans.PostId = cu.PostId
            AND c_ans.UserId = cu.UserId
            AND c_ans.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'
            AND c_ans.Score >= 1
        )
    AND cu.PostId IN (SELECT p_q_sub.AcceptedAnswerId FROM Posts p_q_sub WHERE p_q_sub.Id = cu.ParentId AND p_q_sub.ClosedDate IS NULL)
ORDER BY
    WeightedEngagementScore DESC, Reputation DESC
LIMIT 500;