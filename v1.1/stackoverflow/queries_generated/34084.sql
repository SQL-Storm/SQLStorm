-- {"query": "34084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1027} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        SUM(vt.Name = 'UpMod'::varchar)::int AS UpVotesGiven,
        SUM(vt.Name = 'DownMod'::varchar)::int AS DownVotesGiven,
        COUNT(b.Id) AS BadgeCount,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10, 11)) AS CloseReopenActivities
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViews
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    ORDER BY PostCount DESC
    LIMIT 10
),
ComplexPostStats AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName AS OwnerName,
        ARRAY_AGG(DISTINCT c.Text) FILTER (WHERE c.Score > 2) AS HighScoreComments,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        SUM(vt.Name = 'UpMod'::varchar)::int AS UpVotes,
        SUM(vt.Name = 'DownMod'::varchar)::int AS DownVotes,
        STRING_AGG(DISTINCT lt.Name, ', ') AS LinkTypes,
        COUNT(DISTINCT pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinks
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, u.DisplayName
    HAVING COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) > 2
),
RankedPosts AS (
    SELECT *,
           RANK() OVER (PARTITION BY OwnerName ORDER BY Score DESC, ViewCount DESC) AS RankByUser
    FROM ComplexPostStats
),
FinalResult AS (
    SELECT
        ua.UserId,
        ua.DisplayName AS UserDisplayName,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.AvgPostScore,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.BadgeCount,
        ua.CloseReopenActivities,
        tp.TagName AS TopTag,
        tp.PostCount AS TopTagPostCount,
        tp.AvgScore AS TopTagAvgScore,
        rp.Id AS PostId,
        rp.Title AS PostTitle,
        rp.CreationDate AS PostCreationDate,
        rp.Score AS PostScore,
        rp.ViewCount AS PostViewCount,
        rp.AnswerCount AS PostAnswerCount,
        rp.HighScoreComments,
        rp.EditCount,
        rp.UpVotes AS PostUpVotes,
        rp.DownVotes AS PostDownVotes,
        rp.LinkTypes,
        rp.DuplicateLinks,
        rp.RankByUser
    FROM UserActivity ua
    LEFT JOIN TopTags tp ON TRUE
    LEFT JOIN RankedPosts rp ON rp.OwnerName = ua.DisplayName AND rp.RankByUser = 1
    WHERE ua.QuestionsPosted > 10 AND ua.AvgPostScore IS NOT NULL
    ORDER BY ua.BadgeCount DESC, ua.Reputation DESC NULLS LAST
    LIMIT 50
)
SELECT * FROM FinalResult;
