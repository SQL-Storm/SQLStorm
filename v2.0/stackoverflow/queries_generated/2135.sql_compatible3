WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        1 AS Depth,
        CAST(ARRAY[t.Id] AS INTEGER[]) AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        parent.Depth + 1,
        parent.Path || CAST(ARRAY[child.Id] AS INTEGER[])
    FROM Tags child
    JOIN PostLinks pl ON pl.PostId = child.ExcerptPostId
    JOIN RecursiveTagHierarchy parent ON pl.RelatedPostId = parent.Id
    WHERE NOT (child.Id = ANY(parent.Path))
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesReceived,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS ScoreRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId IS DISTINCT FROM u.Id
    WHERE u.Reputation > 1000 AND u.CreationDate < CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
PostHistCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS INTEGER) ELSE NULL END) AS CloseReasonId,
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVoteCount,
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenVoteCount,
        MAX(ph.CreationDate) AS LastCloseActionDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.PostId
),
TopBadges AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        COUNT(*) OVER (PARTITION BY b.UserId) AS UserBadgeCount,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.Class IN (1, 2)
),
QuestionsWithAnswerInfo AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.OwnerUserId AS AnswererUserId,
        a.Title AS AnswerTitle
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1 AND q.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
),
QuestionTagDetail AS (
    SELECT
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags FROM 2 FOR char_length(q.Tags) - 2), '><')) AS Tag
    FROM QuestionsWithAnswerInfo q
),
UserTagParticipation AS (
    SELECT 
        qtd.Tag,
        ups.UserId,
        COUNT(*) AS PostsCount,
        SUM(q.Score) AS TotalQuestionScore
    FROM QuestionTagDetail qtd
    JOIN Posts p ON (
        (p.PostTypeId = 2 AND p.ParentId = qtd.QuestionId) OR
        (p.PostTypeId = 1 AND p.Id = qtd.QuestionId)
    )
    JOIN UserPostStats ups ON ups.UserId = p.OwnerUserId
    JOIN Posts q ON q.Id = qtd.QuestionId
    GROUP BY qtd.Tag, ups.UserId
),
RankedUsersPerTag AS (
    SELECT
        utp.Tag,
        utp.UserId,
        utp.PostsCount,
        utp.TotalQuestionScore,
        RANK() OVER (PARTITION BY utp.Tag ORDER BY utp.PostsCount DESC, utp.TotalQuestionScore DESC) AS TagUserRank
    FROM UserTagParticipation utp
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommented,
        COUNT(*) AS TotalComments,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
CombinedUserActivity AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.QuestionsCount,
        ups.AnswersCount,
        ups.TotalScore,
        ups.UpVotesReceived,
        ups.DownVotesReceived,
        ups.LastPostDate,
        uba.Name AS TopBadgeName,
        uba.Class AS TopBadgeClass,
        uca.DistinctPostsCommented,
        uca.TotalComments,
        uca.LastCommentDate,
        ARRAY(
            SELECT DISTINCT rtp.Tag
            FROM RankedUsersPerTag rtp
            WHERE rtp.UserId = ups.UserId AND rtp.TagUserRank = 1
            LIMIT 5
        ) AS TopTags
    FROM UserPostStats ups
    LEFT JOIN LATERAL (
        SELECT Name, Class FROM TopBadges WHERE UserId = ups.UserId AND BadgeRank = 1
    ) uba ON TRUE
    LEFT JOIN UserCommentActivity uca ON uca.UserId = ups.UserId
)
SELECT 
    cua.UserId,
    cua.DisplayName,
    cua.QuestionsCount,
    cua.AnswersCount,
    cua.TotalScore,
    cua.UpVotesReceived,
    cua.DownVotesReceived,
    CASE WHEN cua.LastPostDate IS NOT NULL THEN EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - cua.LastPostDate)) ELSE NULL END AS DaysSinceLastPost,
    cua.TopBadgeName,
    CASE cua.TopBadgeClass
        WHEN 1 THEN 'Gold'
        WHEN 2 THEN 'Silver'
        WHEN 3 THEN 'Bronze'
        ELSE 'None'
    END AS TopBadgeClass,
    cua.DistinctPostsCommented,
    cua.TotalComments,
    cua.LastCommentDate,
    cua.TopTags,
    (
      SELECT AVG(ps.Score) 
      FROM Posts ps 
      WHERE ps.OwnerUserId = cua.UserId AND ps.PostTypeId = 2 AND ps.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 year'
    ) AS AvgAnswerScoreLastYear,
    (
      SELECT COUNT(DISTINCT ph.PostId)
      FROM PostHistory ph
      WHERE ph.UserId = cua.UserId AND ph.PostHistoryTypeId = 24 AND ph.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 year'
    ) AS SuggestedEditCountLastYear,
    (
      SELECT COUNT(1)
      FROM Posts p2
      LEFT JOIN PostHistCloseInfo phr ON phr.PostId = p2.Id
      WHERE p2.OwnerUserId = cua.UserId AND phr.CloseReasonId IS NOT NULL AND phr.CloseVoteCount >= 3
    ) AS ClosedPostsCount
FROM CombinedUserActivity cua
WHERE cua.QuestionsCount > 10
ORDER BY cua.TotalScore DESC
LIMIT 50;