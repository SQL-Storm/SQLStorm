-- {"query": "3084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1114} 
WITH RecentPostHistories AS (
    SELECT ph.PostId, ph.Id AS HistoryId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId AS EditorId, ph.Comment
    FROM PostHistory ph
    WHERE ph.CreationDate > (SELECT MAX(CreationDate) FROM Posts) - INTERVAL '30 days'
),
ActiveUsers AS (
    SELECT u.Id AS UserId, u.Reputation, COUNT(c.Id) AS CommentCount, MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation
),
PostAnswerStats AS (
    SELECT p.Id AS QuestionId,
        COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS TotalAnswers,
        AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
        MAX(a.LastActivityDate) FILTER (WHERE a.PostTypeId = 2) AS LastAnswerActivity
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
QuestionTags AS (
    SELECT p.Id AS QuestionId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopTags AS (
    SELECT Tag, COUNT(*) AS TagCount
    FROM QuestionTags
    GROUP BY Tag
    ORDER BY TagCount DESC
    LIMIT 10
),
RecentVotes AS (
    SELECT v.PostId, v.VoteTypeId, v.CreationDate, v.UserId AS VoterId
    FROM Votes v
    WHERE v.CreationDate > (SELECT MAX(CreationDate) FROM Posts) - INTERVAL '7 days'
),
Links AS (
    SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkType
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
UserReputationChange AS (
    SELECT u.Id AS UserId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS ReputationDelta
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.Views,
    (u.UpVotes - u.DownVotes) AS NetVotes,
    ac.CommentCount,
    ac.LastCommentDate,
    pe.TotalAnswers,
    pe.AvgAnswerScore,
    pe.LastAnswerActivity,
    array_agg(DISTINCT tt.Tag) AS TopQuestionTags,
    ARRAY(SELECT rt.Name FROM TopTags tt2 JOIN (SELECT Tag FROM QuestionTags GROUP BY Tag) tt3 ON tt2.Tag = tt3.Tag) AS MostCommonTags,
    JSON_AGG(jsonb_build_object(
        'HistoryId', rph.HistoryId,
        'Type', rph.PostHistoryTypeId,
        'Date', rph.CreationDate,
        'EditorId', rph.UserId,
        'Comment', rph.Comment
    )) FILTER (WHERE rph.PostId IS NOT NULL) AS RecentHistories,
    ARRAY(
        SELECT jsonb_build_object(
            'RelatedPostId', l.RelatedPostId,
            'LinkType', l.LinkType
        )
        FROM Links l
        WHERE l.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
    ) AS UserLinks,
    JSON_AGG(DISTINCT rv.VoteTypeId) AS RecentVoteTypes,
    REPLACE(COALESCE(string_agg(DISTINCT t.TagName, ', '), ''), ' ', '') AS UserTags,
    u.EmailHash AS EmailHashPlaceholder,
    u.ProfileImageUrl,
    u.Location,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgesCount
FROM Users u
LEFT JOIN Comments ac ON u.Id = ac.UserId
LEFT JOIN PostAnswerStats pe ON pe.QuestionId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
)
LEFT JOIN RecentVotes rv ON rv.UserId = u.Id
LEFT JOIN UserReputationChange urc ON u.Id = urc.UserId
LEFT JOIN PostTags pt ON pt.PostId = u.Id
LEFT JOIN Tags t ON t.Id = pt.TagId
LEFT JOIN RecentPostHistories rph ON rph.UserId = u.Id
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS PostCount
    FROM Posts WHERE OwnerUserId <> -1
    GROUP BY OwnerUserId
) pc ON u.Id = pc.OwnerUserId
GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, ac.CommentCount, ac.LastCommentDate,
         pe.TotalAnswers, pe.AvgAnswerScore, pe.LastAnswerActivity,
         u.EmailHash, u.ProfileImageUrl, u.Location
ORDER BY u.Reputation DESC
LIMIT 50;