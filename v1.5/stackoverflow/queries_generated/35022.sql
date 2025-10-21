-- {"query": "35022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 823} 
WITH PopularTags AS (
    SELECT t.Id, t.TagName, t.Count
    FROM Tags t
    WHERE t.Count > (SELECT AVG(Count) FROM Tags)
    ORDER BY t.Count DESC
    LIMIT 50
),
TopQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.Tags, p.Score, p.ViewCount, p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score >= 10
      AND p.ViewCount >= 1000
      AND p.Tags IS NOT NULL
      AND array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) > 0
),
QuestionsWithPopularTags AS (
    SELECT q.*, t.TagName
    FROM TopQuestions q
    JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS tag(TagName) ON TRUE
    JOIN PopularTags t ON tag.TagName = t.TagName
),
ActiveAnswerers AS (
    SELECT pa.ParentId AS QuestionId, pa.OwnerUserId AS UserId, COUNT(*) AS AnswerCount, SUM(pa.Score) AS TotalScore
    FROM Posts pa
    WHERE pa.PostTypeId = 2
      AND pa.OwnerUserId IS NOT NULL
      AND pa.Score > 0
    GROUP BY pa.ParentId, pa.OwnerUserId
    HAVING COUNT(*) >= 2 AND SUM(pa.Score) >= 5
),
QuestionEditors AS (
    SELECT ph.PostId, ph.UserId, COUNT(*) AS Edits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.UserId IS NOT NULL
    GROUP BY ph.PostId, ph.UserId
    HAVING COUNT(*) > 1
),
RecentComments AS (
    SELECT c.PostId, COUNT(*) AS RecentComments, MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate >= (NOW() - INTERVAL '30 days')
    GROUP BY c.PostId
),
BadgeUsers AS (
    SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT qp.QuestionId, qp.Title, qp.TagName, qp.Score, qp.ViewCount,
       u.DisplayName AS OwnerName, u.Reputation,
       aa.UserId AS TopAnswererId, au.DisplayName AS TopAnswererName, aa.TotalScore AS AnswererTotalScore,
       qu.UserId AS TopEditorId, eu.DisplayName AS TopEditorName, qu.Edits AS EditorEdits,
       rc.RecentComments, rc.LastCommentDate,
       bu.GoldBadges, bu.SilverBadges, bu.BronzeBadges
FROM QuestionsWithPopularTags qp
LEFT JOIN Users u ON qp.OwnerUserId = u.Id
LEFT JOIN LATERAL (
    SELECT aa.UserId, aa.TotalScore FROM ActiveAnswerers aa
    WHERE aa.QuestionId = qp.QuestionId
    ORDER BY aa.TotalScore DESC LIMIT 1
) aa ON TRUE
LEFT JOIN Users au ON aa.UserId = au.Id
LEFT JOIN LATERAL (
    SELECT qe.UserId, qe.Edits FROM QuestionEditors qe
    WHERE qe.PostId = qp.QuestionId
    ORDER BY qe.Edits DESC LIMIT 1
) qu ON TRUE
LEFT JOIN Users eu ON qu.UserId = eu.Id
LEFT JOIN RecentComments rc ON rc.PostId = qp.QuestionId
LEFT JOIN BadgeUsers bu ON bu.UserId = qp.OwnerUserId
ORDER BY qp.Score DESC, qp.ViewCount DESC
LIMIT 100;