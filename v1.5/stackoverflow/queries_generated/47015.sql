-- {"query": "47015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1860}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] as tag_path,
        1 as depth
    FROM Tags t
    WHERE t.Count > 10000
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        th.tag_path || t2.TagName,
        th.depth + 1
    FROM Tags t2
    INNER JOIN tag_hierarchy th ON true
    WHERE t2.Count BETWEEN 1000 AND 10000
        AND th.depth < 3
        AND NOT t2.TagName = ANY(th.tag_path)
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array,
        COUNT(DISTINCT p.Id) as QuestionCount,
        SUM(p.Score) as TotalQuestionScore,
        AVG(p.Score) as AvgQuestionScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore,
        STDDEV(p.Score) as ScoreStdDev
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
        AND u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, u.Reputation, p.Tags
),
answer_quality AS (
    SELECT 
        a.OwnerUserId,
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        q.Score as QuestionScore,
        a.CreationDate as AnswerDate,
        q.CreationDate as QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as HoursToAnswer,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END as IsAccepted,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.Score DESC) as answer_rank,
        DENSE_RANK() OVER (PARTITION BY q.Id ORDER BY a.CreationDate) as answer_position
    FROM Posts q
    INNER JOIN Posts a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND a.Score > 0
        AND q.AnswerCount > 3
),
edit_patterns AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        COUNT(*) OVER (PARTITION BY ph.PostId, ph.UserId) as edits_per_user_post,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as prev_edit_time,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate)))/3600 as hours_between_edits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
),
badge_progression AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        LEAD(b.Date) OVER (PARTITION BY b.UserId, b.Name ORDER BY b.Date) as next_badge_date,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as cumulative_badges
    FROM Badges b
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.QuestionCount,
    ue.TotalQuestionScore,
    ROUND(ue.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    ue.MedianScore,
    ROUND(ue.ScoreStdDev::numeric, 2) as ScoreStdDev,
    COUNT(DISTINCT aq.AnswerId) as HighQualityAnswers,
    SUM(aq.IsAccepted) as AcceptedAnswers,
    AVG(aq.HoursToAnswer) FILTER (WHERE aq.answer_position = 1) as AvgHoursToFirstAnswer,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY aq.AnswerScore) as Answer25thPercentile,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY aq.AnswerScore) as Answer75thPercentile,
    COUNT(DISTINCT ep.PostId) as EditedPosts,
    AVG(ep.hours_between_edits) FILTER (WHERE ep.hours_between_edits IS NOT NULL) as AvgHoursBetweenEdits,
    COUNT(DISTINCT bp.Name) FILTER (WHERE bp.Class = 1) as GoldBadges,
    COUNT(DISTINCT bp.Name) FILTER (WHERE bp.Class = 2) as SilverBadges,
    COUNT(DISTINCT bp.Name) FILTER (WHERE bp.Class = 3) as BronzeBadges,
    MAX(bp.cumulative_badges) as TotalBadges,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) as UpvotedPosts,
    COUNT(DISTINCT c.Id) FILTER (WHERE c.Score >= 5) as HighScoringComments,
    ARRAY_AGG(DISTINCT unnest_tags.tag ORDER BY unnest_tags.tag) FILTER (WHERE unnest_tags.tag IS NOT NULL) as ExpertiseTags
FROM user_expertise ue
LEFT JOIN answer_quality aq ON aq.OwnerUserId = ue.UserId AND aq.answer_rank <= 50
LEFT JOIN edit_patterns ep ON ep.UserId = ue.UserId
LEFT JOIN badge_progression bp ON bp.UserId = ue.UserId
LEFT JOIN Votes v ON v.UserId = ue.UserId AND v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
LEFT JOIN Comments c ON c.UserId = ue.UserId
LEFT JOIN LATERAL unnest(ue.tag_array) as unnest_tags(tag) ON true
WHERE ue.QuestionCount >= 10
GROUP BY 
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.QuestionCount,
    ue.TotalQuestionScore,
    ue.AvgQuestionScore,
    ue.MedianScore,
    ue.ScoreStdDev
HAVING COUNT(DISTINCT aq.AnswerId) > 5
ORDER BY 
    ue.Reputation DESC,
    ue.TotalQuestionScore DESC
LIMIT 100;
