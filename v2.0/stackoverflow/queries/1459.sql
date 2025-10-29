-- {"query": "1459.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3375}
WITH UserEngagementStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT b.Id) AS TotalBadgesCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.TagBased THEN 1 ELSE 0 END) AS TagBasedBadgesCount,
        AVG(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate))) AS AvgSecondsBetweenAccessAndCreation,
        (SELECT COUNT(DISTINCT v.PostId) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 5) AS FavoritePostsCount,
        u.Views
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
    HAVING COUNT(DISTINCT b.Id) > 0
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        LENGTH(p.Body) AS BodyCharLength,
        LENGTH(p.Title) AS TitleCharLength,
        p.Tags,
        p.FavoriteCount,
        COUNT(DISTINCT c.Id) AS TotalCommentCount,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS RegisteredUserCommentCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.CreationDate ELSE NULL END) AS LastTagEditDate,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvoteCount,
        p.Title
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.Body IS NOT NULL AND p.Title IS NOT NULL AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Body, p.Title, p.Tags, p.FavoriteCount
),
QuestionAnswerRelations AS (
    SELECT
        q.Id AS QuestionId,
        q.AcceptedAnswerId,
        qa.OwnerUserId AS AnswerOwnerUserId,
        qa.Score AS AnswerScore,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ';'), 'NoTags') AS QuestionTagsList,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostsCount
    FROM Posts q
    LEFT JOIN Posts qa ON q.AcceptedAnswerId = qa.Id AND qa.PostTypeId = 2
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId
    LEFT JOIN LATERAL (SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS tag_name) ln ON TRUE
    LEFT JOIN Tags t ON t.TagName = ln.tag_name
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.AcceptedAnswerId, qa.OwnerUserId, qa.Score
),
HighReputationTagExperts AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostsInTag,
        SUM(p.Score) AS TotalTagScore,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC, COUNT(p.Id) DESC) AS TagExpertRank
    FROM UserEngagementStats ue
    JOIN Posts p ON ue.UserId = p.OwnerUserId
    JOIN LATERAL (SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name) ln ON TRUE
    JOIN Tags t ON t.TagName = ln.tag_name
    WHERE ue.Reputation > 5000 AND p.PostTypeId = 1
    GROUP BY ue.UserId, ue.DisplayName, t.TagName
    HAVING COUNT(p.Id) >= 5
),
UserPostAggregates AS (
    SELECT
        pca.OwnerUserId AS UserId,
        COUNT(DISTINCT pca.PostId) AS UserRelevantPostCount,
        SUM(pca.UpvoteCount) AS UserTotalUpvotes,
        SUM(pca.DownvoteCount) AS UserTotalDownvotes,
        MAX(pca.LastBodyEditDate) AS UserLatestPostEditDate
    FROM PostContentAnalysis pca
    WHERE
        pca.PostTypeId = 1
        AND pca.PostScore > 20
        AND pca.ViewCount > 1000
        AND pca.RegisteredUserCommentCount > 0
        AND (pca.Tags LIKE '%<sql>%' OR pca.Tags LIKE '%<database>%')
    GROUP BY pca.OwnerUserId
    HAVING
        COUNT(DISTINCT pca.PostId) > 1
        AND SUM(pca.UpvoteCount) > SUM(pca.DownvoteCount) * 1.5
        AND MAX(pca.LastBodyEditDate) IS NOT NULL
),
Part1 AS (
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        pca.PostId,
        pca.Title,
        pca.PostScore,
        pca.ViewCount,
        pca.FavoriteCount,
        pca.TotalCommentCount,
        pca.RegisteredUserCommentCount,
        qar.QuestionTagsList,
        h.TagName AS TopExpertTag,
        h.PostsInTag AS ExpertTagPostsCount,
        h.TotalTagScore AS ExpertTagTotalScore,
        CAST(pca.PostScore AS NUMERIC) / GREATEST(1, pca.ViewCount) AS CalculatedRatio,
        (pca.UpvoteCount - pca.DownvoteCount) AS NetActivity,
        COALESCE(
            CASE
                WHEN pca.PostScore > 50 AND pca.FavoriteCount > 5 AND pca.ViewCount > 5000 THEN 'HighlyEngaged'
                WHEN pca.TotalCommentCount > 10 OR pca.RegisteredUserCommentCount > 5 THEN 'Discussed'
                WHEN pca.BodyCharLength > 1000 AND pca.TitleCharLength > 50 THEN 'DetailedContent'
                ELSE 'Standard'
            END, 'UnknownCategory'
        ) AS ImpactCategory,
        (SELECT c_corr.Text
         FROM Comments c_corr
         WHERE c_corr.PostId = pca.PostId AND c_corr.UserId = ues.UserId
         ORDER BY c_corr.CreationDate DESC
         LIMIT 1) AS AdditionalInfo,
        -- replace RANGE with ROWS based on date order converted to number of days window
        AVG(pca.PostScore) OVER (
            PARTITION BY ues.UserId
            ORDER BY pca.PostCreationDate
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ) AS RollingMetric,
        (CASE WHEN pca.LastBodyEditDate IS NOT NULL AND pca.LastBodyEditDate > (pca.PostCreationDate - INTERVAL '30 days') THEN TRUE ELSE FALSE END) AS BooleanFlag,
        DATE_TRUNC('month', pca.PostCreationDate) AS TimePeriod
    FROM UserEngagementStats ues
    INNER JOIN UserPostAggregates upa ON ues.UserId = upa.UserId
    INNER JOIN PostContentAnalysis pca ON ues.UserId = pca.OwnerUserId
    LEFT JOIN QuestionAnswerRelations qar ON pca.PostId = qar.QuestionId
    LEFT JOIN HighReputationTagExperts h ON ues.UserId = h.UserId AND h.TagExpertRank = 1
    WHERE
        ues.Reputation > 1000
        AND ues.AvgSecondsBetweenAccessAndCreation > (365 * 24 * 60 * 60)
        AND EXISTS (SELECT 1 FROM PostHistory ph_corr WHERE ph_corr.PostId = pca.PostId AND ph_corr.PostHistoryTypeId = 11)
        AND (
            (qar.AcceptedAnswerId IS NOT NULL AND qar.AnswerScore > 10)
            OR (qar.LinkedPostsCount > 0 AND qar.DuplicatePostsCount = 0)
        )
    GROUP BY
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        pca.PostId,
        pca.Title,
        pca.PostScore,
        pca.ViewCount,
        pca.FavoriteCount,
        pca.TotalCommentCount,
        pca.RegisteredUserCommentCount,
        qar.QuestionTagsList,
        h.TagName,
        h.PostsInTag,
        h.TotalTagScore,
        pca.BodyCharLength,
        pca.TitleCharLength,
        pca.UpvoteCount,
        pca.DownvoteCount,
        pca.LastBodyEditDate,
        pca.PostCreationDate,
        pca.Tags,
        ues.AvgSecondsBetweenAccessAndCreation
),
AnswererActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalAnswers,
        SUM(p.Score) AS TotalAnswerScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 5 AND SUM(p.Score) > 10
),
ClosedQuestionAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.OwnerUserId AS AnswerOwnerId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.ClosedDate AS QuestionClosedDate,
        COALESCE(
            (SELECT crt.Name FROM PostHistory ph JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10 ORDER BY ph.CreationDate DESC LIMIT 1),
            'Unknown'
        ) AS LatestCloseReasonName,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 1) AS AcceptedVoteCount,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS AnswerDownvoteCount
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 AND q.PostTypeId = 1 AND q.ClosedDate IS NOT NULL
),
Part2 AS (
    SELECT
        aa.UserId,
        aa.DisplayName,
        aa.Reputation,
        cqa.AnswerId AS PostId,
        cqa.QuestionTitle AS Title,
        cqa.AnswerScore AS PostScore,
        CAST(NULL AS INTEGER) AS ViewCount,
        CAST(NULL AS INTEGER) AS FavoriteCount,
        (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.PostId = cqa.AnswerId) AS TotalCommentCount,
        CAST(NULL AS INTEGER) AS RegisteredUserCommentCount,
        CAST(NULL AS TEXT) AS QuestionTagsList,
        CAST(NULL AS VARCHAR) AS TopExpertTag,
        CAST(NULL AS INTEGER) AS ExpertTagPostsCount,
        CAST(NULL AS INTEGER) AS ExpertTagTotalScore,
        CAST(cqa.AnswerScore AS NUMERIC) / GREATEST(1, (cqa.AcceptedVoteCount + 1)) AS CalculatedRatio,
        (cqa.AcceptedVoteCount - cqa.AnswerDownvoteCount) AS NetActivity,
        CAST('AnswerToClosedQuestion' AS TEXT) AS ImpactCategory,
        cqa.LatestCloseReasonName AS AdditionalInfo,
        -- replace RANGE with ROWS based on approximate days window
        AVG(cqa.AnswerScore) OVER (
            PARTITION BY aa.UserId
            ORDER BY cqa.AnswerCreationDate
            ROWS BETWEEN 183 PRECEDING AND CURRENT ROW
        ) AS RollingMetric,
        (CASE WHEN cqa.QuestionClosedDate IS NOT NULL AND cqa.AnswerCreationDate < cqa.QuestionClosedDate THEN TRUE ELSE FALSE END) AS BooleanFlag,
        DATE_TRUNC('month', cqa.AnswerCreationDate) AS TimePeriod
    FROM AnswererActivity aa
    JOIN ClosedQuestionAnswers cqa ON aa.UserId = cqa.AnswerOwnerId
    WHERE
        aa.Reputation > 2000
        AND cqa.AnswerScore > 5
        AND cqa.AcceptedVoteCount > 0
        AND cqa.QuestionClosedDate IS NOT NULL
    GROUP BY
        aa.UserId,
        aa.DisplayName,
        aa.Reputation,
        cqa.AnswerId,
        cqa.QuestionTitle,
        cqa.AnswerScore,
        cqa.AnswerCreationDate,
        cqa.AcceptedVoteCount,
        cqa.AnswerDownvoteCount,
        cqa.LatestCloseReasonName,
        cqa.QuestionClosedDate
),
CombinedResults AS (
    SELECT * FROM Part1
    UNION ALL
    SELECT * FROM Part2
)
SELECT *
FROM CombinedResults
ORDER BY Reputation DESC, PostScore DESC, RollingMetric DESC
LIMIT 700;