-- {"query": "2272.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1912}
WITH RecursiveTags AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(p.Title, '') AS ExcerptTitle,
        COALESCE(p.Body, '') AS ExcerptBody,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE
),
FilteredTags AS (
    SELECT Id, TagName, Count, ExcerptTitle, ExcerptBody
    FROM RecursiveTags
    WHERE rn = 1
),
RecentActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(LENGTH(COALESCE(vt.Name, '')), 0)) AS AvgVoteTypeNameLength
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(p.Id) > 5
),
BadgesPerUser AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS RecentBadges
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN b.BadgeCount ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN b.BadgeCount ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN b.BadgeCount ELSE 0 END), 0) AS BronzeBadges,
        STRING_AGG(DISTINCT b.RecentBadges, '; ') AS AllRecentBadges
    FROM RecentActiveUsers u
    LEFT JOIN BadgesPerUser b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostDetails AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.AcceptedAnswerId,
        pa.Score AS AcceptedAnswerScore,
        COALESCE(lnk.LinkCount, 0) AS LinkCountToDuplicates,
        COALESCE(cm.CommentCount, 0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Posts pa ON pa.Id = p.AcceptedAnswerId AND p.PostTypeId = 1
    LEFT JOIN (
        SELECT
            l.PostId,
            COUNT(*) AS LinkCount
        FROM PostLinks l
        WHERE l.LinkTypeId = 3
        GROUP BY l.PostId
    ) lnk ON lnk.PostId = p.Id
    LEFT JOIN (
        SELECT
            c.PostId,
            COUNT(*) AS CommentCount
        FROM Comments c
        GROUP BY c.PostId
    ) cm ON cm.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
),
QuestionsWithTopAnswerVotes AS (
    SELECT
        pd.Id AS QuestionId,
        pd.Title,
        pd.OwnerUserId,
        pd.OwnerName,
        pd.Score AS QuestionScore,
        pd.ViewCount,
        pd.LinkCountToDuplicates,
        pd.CommentCount,
        pd.AcceptedAnswerId,
        pd.AcceptedAnswerScore,
        RANK() OVER (PARTITION BY pd.OwnerUserId ORDER BY pd.Score DESC, pd.ViewCount DESC) AS QuestionRank
    FROM PostDetails pd
    WHERE pd.PostTypeId = 1
),
AnswersVoteStats AS (
    SELECT
        p.ParentId AS QuestionId,
        AVG(p.Score) AS AvgAnswerScoreForQuestion,
        MAX(p.Score) AS MaxAnswerScoreForQuestion,
        COUNT(*) AS TotalAnswers
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
PostHistoryCloseEvents AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN cht.Name = 'Post Closed' THEN ph.CreationDate ELSE NULL END) AS LastCloseDate,
        MAX(CASE WHEN cht.Name = 'Post Reopened' THEN ph.CreationDate ELSE NULL END) AS LastReopenDate,
        MAX(CASE WHEN cht.Name = 'Post Closed' THEN NULLIF(REGEXP_REPLACE(ph.Comment, '\D', '', 'g'), '') END) AS LastCloseReasonIdText
    FROM PostHistory ph
    JOIN PostHistoryTypes cht ON cht.Id = ph.PostHistoryTypeId
    WHERE ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.PostId
),
FinalResult AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.OwnerName,
        q.QuestionScore,
        q.ViewCount,
        q.LinkCountToDuplicates,
        q.CommentCount,
        q.AcceptedAnswerId,
        q.AcceptedAnswerScore,
        avs.AvgAnswerScoreForQuestion,
        avs.MaxAnswerScoreForQuestion,
        avs.TotalAnswers,
        phc.LastCloseDate,
        phc.LastReopenDate,
        CASE WHEN phc.LastCloseReasonIdText ~ '^[0-9]+$' THEN CAST(phc.LastCloseReasonIdText AS integer) ELSE NULL END AS LastCloseReasonId,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.AllRecentBadges,
        ft.TagName,
        ft.Count AS TagUseCount,
        CASE
            WHEN phc.LastCloseDate IS NOT NULL AND (phc.LastReopenDate IS NULL OR phc.LastCloseDate > phc.LastReopenDate) THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus,
        LENGTH(REGEXP_REPLACE(q.Title, '\s+', '', 'g')) AS TitleCharCount,
        CASE
            WHEN q.Title IS NULL THEN NULL
            ELSE array_length(string_to_array(
                -- attempt to derive tags from the Tags column if present, otherwise try from Title pattern
                CASE WHEN q.Title IS NOT NULL AND q.Title LIKE '%<%>%'
                     THEN substring(q.Title FROM 2 FOR char_length(q.Title) - 2)
                     ELSE q.Title END
            , '><'), 1)
        END AS NumberOfTags,
        (SELECT COUNT(*)
         FROM Posts p2
         WHERE p2.OwnerUserId = q.OwnerUserId
           AND p2.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month') AS UserRecentPostCount
    FROM QuestionsWithTopAnswerVotes q
    LEFT JOIN AnswersVoteStats avs ON avs.QuestionId = q.QuestionId
    LEFT JOIN PostHistoryCloseEvents phc ON phc.PostId = q.QuestionId
    LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = q.OwnerUserId
    LEFT JOIN FilteredTags ft ON ft.TagName = ANY (string_to_array(regexp_replace(q.Title, '[^a-zA-Z0-9_\- ]', ' ', 'g'), ' '))
    WHERE q.QuestionRank <= 10
    GROUP BY
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.OwnerName,
        q.QuestionScore,
        q.ViewCount,
        q.LinkCountToDuplicates,
        q.CommentCount,
        q.AcceptedAnswerId,
        q.AcceptedAnswerScore,
        avs.AvgAnswerScoreForQuestion,
        avs.MaxAnswerScoreForQuestion,
        avs.TotalAnswers,
        phc.LastCloseDate,
        phc.LastReopenDate,
        phc.LastCloseReasonIdText,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.AllRecentBadges,
        ft.TagName,
        ft.Count
)
SELECT
    QuestionId,
    Title,
    OwnerUserId,
    OwnerName,
    QuestionScore,
    ViewCount,
    LinkCountToDuplicates,
    CommentCount,
    AcceptedAnswerId,
    AcceptedAnswerScore,
    AvgAnswerScoreForQuestion,
    MaxAnswerScoreForQuestion,
    TotalAnswers,
    LastCloseDate,
    LastReopenDate,
    LastCloseReasonId,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AllRecentBadges,
    TagName,
    TagUseCount,
    PostStatus,
    TitleCharCount,
    NumberOfTags,
    UserRecentPostCount,
    RANK() OVER (PARTITION BY PostStatus ORDER BY QuestionScore DESC, ViewCount DESC) AS RankWithinStatus,
    CASE
        WHEN GoldBadges > 0 THEN CAST(GoldBadges AS varchar)
        ELSE '0'
    END || 'G/' ||
    CASE
        WHEN SilverBadges > 0 THEN CAST(SilverBadges AS varchar)
        ELSE '0'
    END || 'S/' ||
    CASE
        WHEN BronzeBadges > 0 THEN CAST(BronzeBadges AS varchar)
        ELSE '0'
    END || 'B' AS BadgeSummary,
    LEFT(Title, 30) || '... [' || COALESCE(CAST(NumberOfTags AS varchar), '0') || ' tags]' AS TitlePreviewWithTags
FROM FinalResult
ORDER BY RankWithinStatus, QuestionScore DESC
LIMIT 50;