-- {"query": "3299.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1813}
WITH RECURSIVE TagTree AS (
    SELECT
        t.Id            AS TagId,
        t.TagName       AS TagName,
        t.Count         AS TagPostCount,
        0               AS Depth,
        CAST(t.TagName AS varchar(4000)) AS Path
    FROM Tags t
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        tt.Depth + 1,
        CAST(tt.Path || ' > ' || t.TagName AS varchar(4000)) AS Path
    FROM Tags t
    JOIN TagTree tt ON FALSE
),
RecentQuestions AS (
    SELECT
        p.Id               AS QuestionId,
        p.CreationDate    AS QCreated,
        p.Score           AS QScore,
        p.ViewCount       AS QViews,
        p.OwnerUserId     AS QOwnerId,
        p.Title           AS QTitle,
        regexp_replace(p.Tags, '^<|>$', '', 'g')               AS CleanTags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 day'
),
QuestionTagMap AS (
    SELECT
        q.QuestionId,
        q.QCreated,
        q.QScore,
        q.QViews,
        q.QOwnerId,
        q.QTitle,
        t.TagExtract                            AS TagName,
        ROW_NUMBER() OVER (PARTITION BY q.QuestionId ORDER BY t.TagExtract) AS TagSeq
    FROM RecentQuestions q
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(q.CleanTags, '><')) AS TagExtract
    ) t
),
AnswerStats AS (
    SELECT
        a.ParentId                               AS QuestionId,
        a.Id                                      AS AnswerId,
        a.OwnerUserId                             AS AnswerOwnerId,
        a.CreationDate                           AS ACreated,
        a.Score                                   AS AScore,
        CASE WHEN a.Id = qq.AcceptedAnswerId THEN 1 ELSE 0 END   AS IsAccepted,
        COALESCE(v.UpVotes,0)                     AS UpVoteCount,
        COALESCE(v.DownVotes,0)                   AS DownVoteCount
    FROM Posts a
    JOIN QuestionTagMap qtm ON a.ParentId = qtm.QuestionId
    -- need to reference the Posts row for the question to get AcceptedAnswerId
    JOIN Posts qq ON qq.Id = qtm.QuestionId
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        GROUP BY v.PostId
    ) v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
),
UserBadgeLatest AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
),
UserScoring AS (
    SELECT
        u.Id                                 AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(a.AScore),0)            AS TotalAnswerScore,
        COALESCE(SUM(a.IsAccepted),0)        AS AcceptedAnswers,
        COALESCE(SUM(a.UpVoteCount),0)       AS TotalUpVotes,
        COALESCE(SUM(a.DownVoteCount),0)     AS TotalDownVotes,
        COALESCE(COUNT(DISTINCT a.QuestionId),0) AS DistinctQuestionsAnswered,
        COALESCE(MAX(b.Date), NULL)          AS LatestBadgeDate,
        COALESCE(MAX(CASE WHEN b.Class = 1 THEN b.Name END), NULL) AS GoldBadge,
        COALESCE(MAX(CASE WHEN b.Class = 2 THEN b.Name END), NULL) AS SilverBadge,
        COALESCE(MAX(CASE WHEN b.Class = 3 THEN b.Name END), NULL) AS BronzeBadge
    FROM Users u
    LEFT JOIN AnswerStats a ON a.AnswerOwnerId = u.Id
    LEFT JOIN UserBadgeLatest b ON b.UserId = u.Id AND b.rn = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagUserActivity AS (
    SELECT
        tqm.TagName,
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalAnswerScore,
        us.AcceptedAnswers,
        us.TotalUpVotes,
        us.TotalDownVotes,
        us.DistinctQuestionsAnswered,
        us.GoldBadge,
        us.SilverBadge,
        us.BronzeBadge,
        ROW_NUMBER() OVER (PARTITION BY tqm.TagName
                           ORDER BY us.TotalAnswerScore DESC,
                                    us.TotalUpVotes DESC,
                                    us.Reputation DESC) AS RankInTag
    FROM QuestionTagMap tqm
    JOIN AnswerStats a ON a.QuestionId = tqm.QuestionId
    JOIN UserScoring us ON us.UserId = a.AnswerOwnerId
    WHERE a.IsAccepted = 1
),
TopTagContributors AS (
    SELECT *
    FROM TagUserActivity
    WHERE RankInTag <= 5
),
TagLinkMetrics AS (
    SELECT
        lt.TagName,
        COUNT(DISTINCT lt.PostId)          AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId END) AS DuplicateLinksCount
    FROM (
        SELECT DISTINCT
            regexp_replace(p.Tags, '^<|>$', '', 'g')         AS CleanTags,
            unnest(string_to_array(regexp_replace(p.Tags, '^<|>$', '', 'g'), '><')) AS TagName,
            p.Id                                            AS PostId
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) lt
    LEFT JOIN PostLinks pl ON pl.PostId = lt.PostId
    GROUP BY lt.TagName
)
SELECT
    tt.TagId,
    tt.TagName,
    tt.TagPostCount,
    COALESCE(tl.LinkedPostsCount,0)        AS LinkedPosts,
    COALESCE(tl.DuplicateLinksCount,0)     AS Duplicates,
    tc.UserId,
    tc.DisplayName,
    tc.Reputation,
    tc.TotalAnswerScore,
    tc.AcceptedAnswers,
    tc.TotalUpVotes,
    tc.TotalDownVotes,
    tc.DistinctQuestionsAnswered,
    tc.GoldBadge,
    tc.SilverBadge,
    tc.BronzeBadge,
    tc.RankInTag
FROM TagTree tt
LEFT JOIN TopTagContributors tc ON tc.TagName = tt.TagName
LEFT JOIN TagLinkMetrics tl ON tl.TagName = tt.TagName
GROUP BY
    tt.TagId,
    tt.TagName,
    tt.TagPostCount,
    tl.LinkedPostsCount,
    tl.DuplicateLinksCount,
    tc.UserId,
    tc.DisplayName,
    tc.Reputation,
    tc.TotalAnswerScore,
    tc.AcceptedAnswers,
    tc.TotalUpVotes,
    tc.TotalDownVotes,
    tc.DistinctQuestionsAnswered,
    tc.GoldBadge,
    tc.SilverBadge,
    tc.BronzeBadge,
    tc.RankInTag
ORDER BY tt.TagPostCount DESC,
         tc.RankInTag ASC NULLS LAST,
         tt.TagName;