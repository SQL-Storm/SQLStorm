WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        CAST(t.TagName AS VARCHAR(1000)) AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1 AS Level,
        CAST(r.Path || ' > ' || t2.TagName AS VARCHAR(1000)) AS Path
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id = r.Id + 1 AND t2.IsModeratorOnly = false
    WHERE r.Level < 3
),
UserBadgeRankings AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(u.WebsiteUrl, '') AS WebsiteUrl,
        COALESCE(u.AboutMe, '') AS AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(b.BadgeCount, 0) AS TotalBadges,
        COALESCE(b.Class, 0) AS TopBadgeClass
    FROM Users u
    LEFT JOIN (
        SELECT UserId, Class, SUM(BadgeCount) AS BadgeCount
        FROM UserBadgeRankings
        WHERE rn = 1
        GROUP BY UserId, Class
    ) b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
),
PostAnswerStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        COALESCE(a.AnswerCount, 0) AS ActualAnswerCount,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore
    FROM Posts p
    LEFT JOIN (
        SELECT
            ParentId,
            COUNT(*) AS AnswerCount,
            MAX(Score) AS MaxAnswerScore,
            AVG(Score) AS AvgAnswerScore
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON p.Id = a.ParentId
    WHERE p.PostTypeId = 1
),
PostCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReasonId,
        MAX(ph.CreationDate) AS CloseDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate IS NOT NULL
),
UserRecentPosts AS (
    SELECT
        UserId,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS RecentQuestions,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS RecentAnswers,
        AVG(Score) AS AvgRecentScore
    FROM UserActivityWindow
    WHERE RecentPostRank <= 10
    GROUP BY UserId
),
QuestionWithComments AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters
    FROM Posts q
    LEFT JOIN Comments c ON q.Id = c.PostId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
),
DuplicateQuestions AS (
    SELECT DISTINCT pl.PostId AS DuplicateId, pl.RelatedPostId AS OriginalId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),
QuestionsWithDuplicates AS (
    SELECT
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        COALESCE(d.DuplicateCount, 0) AS DuplicateCount
    FROM Posts q
    LEFT JOIN (
        SELECT OriginalId, COUNT(*) AS DuplicateCount
        FROM DuplicateQuestions
        GROUP BY OriginalId
    ) d ON q.Id = d.OriginalId
    WHERE q.PostTypeId = 1
),
FinalSelection AS (
    SELECT
        tu.Id AS UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.Location,
        tu.WebsiteUrl,
        tu.AboutMe,
        tu.Views,
        tu.UpVotes,
        tu.DownVotes,
        tu.TotalBadges,
        tu.TopBadgeClass,
        ua.RecentQuestions,
        ua.RecentAnswers,
        ua.AvgRecentScore,
        pas.QuestionId,
        pas.Title AS QuestionTitle,
        pas.CreationDate AS QuestionCreationDate,
        pas.QuestionScore,
        pas.ViewCount AS QuestionViews,
        pas.AnswerCount,
        pas.ActualAnswerCount,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pci.CloseReasonId,
        pci.CloseDate,
        qwc.DuplicateCount,
        qwc.Score AS QuestionOriginalScore,
        qwc.ViewCount AS QuestionOriginalViews,
        qc.CommentCount,
        qc.Commenters,
        rh.Level AS TagLevel,
        rh.Path AS TagPath,
        rh.Count AS TagCount
    FROM TopUsers tu
    LEFT JOIN UserRecentPosts ua ON tu.Id = ua.UserId
    LEFT JOIN PostAnswerStats pas ON pas.OwnerUserId = tu.Id
    LEFT JOIN PostCloseInfo pci ON pas.QuestionId = pci.PostId
    LEFT JOIN QuestionsWithDuplicates qwc ON pas.QuestionId = qwc.Id
    LEFT JOIN QuestionWithComments qc ON pas.QuestionId = qc.QuestionId
    LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(COALESCE(pas.Title, ''), ' '))
    WHERE tu.Reputation > 2000
)
SELECT
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.Location,
    fs.WebsiteUrl,
    SUBSTRING(fs.AboutMe FROM 1 FOR 100) AS AboutMeSnippet,
    fs.Views,
    fs.UpVotes,
    fs.DownVotes,
    fs.TotalBadges,
    CASE fs.TopBadgeClass
        WHEN 1 THEN 'Gold'
        WHEN 2 THEN 'Silver'
        WHEN 3 THEN 'Bronze'
        ELSE 'None'
    END AS TopBadgeClassName,
    fs.RecentQuestions,
    fs.RecentAnswers,
    ROUND(CAST(fs.AvgRecentScore AS NUMERIC), 2) AS AvgRecentScore,
    fs.QuestionId,
    fs.QuestionTitle,
    fs.QuestionCreationDate,
    fs.QuestionScore,
    fs.QuestionViews,
    fs.AnswerCount,
    fs.ActualAnswerCount,
    fs.MaxAnswerScore,
    ROUND(CAST(fs.AvgAnswerScore AS NUMERIC), 2) AS AvgAnswerScore,
    fs.CloseReasonId,
    fs.CloseDate,
    fs.DuplicateCount,
    fs.QuestionOriginalScore,
    fs.QuestionOriginalViews,
    fs.CommentCount,
    fs.Commenters,
    fs.TagLevel,
    fs.TagPath,
    fs.TagCount
FROM FinalSelection fs
WHERE fs.QuestionScore > 5
ORDER BY fs.Reputation DESC, fs.QuestionScore DESC
FETCH FIRST 100 ROWS ONLY;