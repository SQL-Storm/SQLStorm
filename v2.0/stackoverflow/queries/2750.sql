-- {"query": "2750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1166}
WITH RECURSIVE RecursiveTopTags AS (
    SELECT
        t.TagName,
        t.Count,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id AS OwnerUserId,
        u.DisplayName,
        dense_rank() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1
        AND ('<' || t.TagName || '>') = ANY(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><'))
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE t.Count > 5000
    UNION ALL
    SELECT
        r.TagName,
        r.Count,
        pl.PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id,
        u.DisplayName,
        r.TagRank
    FROM RecursiveTopTags r
    JOIN PostLinks pl ON pl.RelatedPostId = r.PostId AND pl.LinkTypeId = 3
    JOIN Posts p ON p.Id = pl.PostId
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > r.CreationDate - INTERVAL '30 day'
      AND r.TagRank <= 5
),
RankedAnswers AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName,
        row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2 AND a.Score IS NOT NULL
),
UserBadgesStats AS (
    SELECT
        b.UserId,
        count(*) AS TotalBadges,
        sum(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        sum(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        sum(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        max(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserActivityWindowed AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        count(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        max(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS MaxPostScore,
        row_number() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC NULLS LAST) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
)
SELECT
    rt.TagRank,
    rt.TagName,
    rt.Count AS TagCount,
    rt.PostId AS QuestionId,
    rt.Score AS QuestionScore,
    rt.ViewCount AS QuestionViews,
    rt.CreationDate AS QuestionCreationDate,
    coalesce(rt.DisplayName, 'anonymous') AS QuestionOwner,
    ra.Id AS TopAnswerId,
    ra.Score AS TopAnswerScore,
    ra.CreationDate AS TopAnswerCreationDate,
    coalesce(ra.DisplayName, 'anonymous') AS TopAnswerOwner,
    uas.UserRank,
    uas.Reputation AS AnswerOwnerReputation,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    CASE
        WHEN ra.Score >= 10 THEN 'Highly Upvoted'
        WHEN ra.Score BETWEEN 5 AND 9 THEN 'Moderately Upvoted'
        WHEN ra.Score < 5 AND ra.Score > 0 THEN 'Low Upvoted'
        ELSE 'Not Upvoted'
    END AS AnswerPopularity,
    CASE
        WHEN rt.ViewCount > 10000 THEN 'Very Popular'
        WHEN rt.ViewCount BETWEEN 1000 AND 9999 THEN 'Popular'
        ELSE 'Normal'
    END AS QuestionPopularityCategory,
    (
        coalesce(uas.Location, 'Unknown') || ' / ' ||
        coalesce(cast(uas.Views AS text), '0') || ' views / ' ||
        coalesce(cast(uas.UpVotes AS text), '0') || ' upvotes / ' ||
        coalesce(cast(uas.DownVotes AS text), '0') || ' downvotes'
    ) AS AnswerOwnerStatsSnippet
FROM RecursiveTopTags rt
LEFT JOIN RankedAnswers ra ON ra.ParentId = rt.PostId AND ra.AnswerRank = 1
LEFT JOIN UserActivityWindowed uas ON uas.Id = ra.OwnerUserId
LEFT JOIN UserBadgesStats ubs ON ubs.UserId = ra.OwnerUserId
WHERE rt.TagRank <= 5
GROUP BY
    rt.TagRank,
    rt.TagName,
    rt.Count,
    rt.PostId,
    rt.Score,
    rt.ViewCount,
    rt.CreationDate,
    rt.DisplayName,
    ra.Id,
    ra.Score,
    ra.CreationDate,
    ra.DisplayName,
    uas.UserRank,
    uas.Reputation,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    uas.Location,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes
ORDER BY rt.TagRank, QuestionScore DESC, TopAnswerScore DESC
LIMIT 100;