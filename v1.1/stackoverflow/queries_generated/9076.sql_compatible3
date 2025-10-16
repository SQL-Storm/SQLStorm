WITH
    PostVoteSummary AS (
        SELECT
            p.Id AS PostId,
            COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
            COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
            COUNT(v.Id) AS TotalVotes,
            SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
        FROM Posts p
        LEFT JOIN Votes v
            ON v.PostId = p.Id
        GROUP BY p.Id
    ),
    RecentUserActivity AS (
        SELECT
            u.Id AS UserId,
            u.Reputation,
            MAX(u.Reputation) OVER () AS MaxReputation,
            CASE
                WHEN u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7' DAY THEN 'Online'
                ELSE 'Offline'
            END AS Status,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
        FROM Users u
    ),
    TagUsage AS (
        SELECT
            p.Id AS PostId,
            TRIM(tag) AS Tag
        FROM Posts p,
             LATERAL (
               SELECT UNNEST(
                 string_to_array(
                   substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)),
                   '><'
                 )
               ) AS tag
             ) t
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ),
    TopTags AS (
        SELECT
            Tag,
            COUNT(*) AS Count,
            RANK() OVER (ORDER BY COUNT(*) DESC) AS TagRank
        FROM TagUsage
        GROUP BY Tag
    ),
    QuestionMetrics AS (
        SELECT
            p.Id,
            p.Title,
            p.OwnerUserId,
            p.CreationDate,
            COALESCE(vs.UpVotes - vs.DownVotes, 0) AS VoteDiff,
            vs.TotalVotes,
            vs.TotalBounty,
            tt.Count AS TagCount,
            tt.TagRank
        FROM Posts p
        LEFT JOIN PostVoteSummary vs
            ON vs.PostId = p.Id
        LEFT JOIN TopTags tt
            ON tt.Tag IN (
                 SELECT UNNEST(
                   string_to_array(
                     substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)),
                     '><'
                   )
                 )
               )
        WHERE p.PostTypeId = 1
    ),
    EnrichedQuestions AS (
        SELECT
            qm.Id,
            qm.Title,
            qm.OwnerUserId,
            qm.CreationDate,
            qm.VoteDiff,
            qm.TotalVotes,
            qm.TotalBounty,
            qm.TagCount,
            qm.TagRank,
            rua.Status,
            rua.RepRank,
            (length(qm.Title) - length(replace(qm.Title, ' ', '')) + 1) AS TitleWordCount,
            CASE
                WHEN qm.VoteDiff > (
                    SELECT AVG(vs.UpVotes - vs.DownVotes)
                    FROM PostVoteSummary vs
                ) THEN 'HighImpact'
                ELSE 'LowImpact'
            END AS ImpactLevel
        FROM QuestionMetrics qm
        LEFT JOIN RecentUserActivity rua
            ON rua.UserId = qm.OwnerUserId
    ),
    Filtered AS (
        SELECT
            eq.Id,
            eq.Title,
            eq.OwnerUserId,
            eq.CreationDate,
            eq.VoteDiff,
            eq.TotalVotes,
            eq.TotalBounty,
            eq.TagCount,
            eq.TagRank,
            eq.Status,
            eq.RepRank,
            eq.TitleWordCount,
            eq.ImpactLevel
        FROM EnrichedQuestions eq
        WHERE eq.TitleWordCount BETWEEN 3 AND 10
          AND EXISTS (
              SELECT 1
                FROM PostHistory ph
               WHERE ph.PostId = eq.Id
                 AND ph.PostHistoryTypeId = 10
          )
    ),
    PopularUsers AS (
        SELECT u.Id
        FROM Users u
        WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users)
    ),
    PopularQuestions AS (
        SELECT eq.Title, eq.VoteDiff, eq.Status, eq.RepRank, eq.TitleWordCount, eq.ImpactLevel
        FROM EnrichedQuestions eq
        WHERE eq.VoteDiff > 10
        INTERSECT
        SELECT eq.Title, eq.VoteDiff, eq.Status, eq.RepRank, eq.TitleWordCount, eq.ImpactLevel
        FROM EnrichedQuestions eq
        WHERE eq.TotalVotes > 20
    )

SELECT fq.Title, fq.VoteDiff, fq.Status, fq.RepRank, fq.TitleWordCount, fq.ImpactLevel, fq.TagRank
FROM Filtered fq
INNER JOIN PopularUsers pu
    ON pu.Id = fq.OwnerUserId

EXCEPT

SELECT e.Title, e.VoteDiff, e.Status, e.RepRank, e.TitleWordCount, e.ImpactLevel, e.TagRank
FROM EnrichedQuestions e
WHERE e.RepRank > 100

UNION

SELECT e2.Title, e2.VoteDiff, e2.Status, e2.RepRank, e2.TitleWordCount, e2.ImpactLevel, e2.TagRank
FROM EnrichedQuestions e2
WHERE e2.ImpactLevel = 'HighImpact'

INTERSECT

SELECT e3.Title, e3.VoteDiff, e3.Status, e3.RepRank, e3.TitleWordCount, e3.ImpactLevel, e3.TagRank
FROM EnrichedQuestions e3
WHERE e3.TotalVotes > 50

ORDER BY VoteDiff DESC, TagRank ASC
LIMIT 100;