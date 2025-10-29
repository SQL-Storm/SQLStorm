-- {"query": "2864.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1390} 
with RecursiveCTE as (
    select 
        p.Id as PostId, 
        p.Score, 
        p.ViewCount,
        u.Reputation as OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 -- questions
), TopQuestionsPerUser as (
    select PostId, Score, ViewCount, OwnerReputation
    from RecursiveCTE
    where rn = 1
), QuestionAnswerStats as (
    select 
        q.PostId as QuestionId,
        q.Score as QuestionScore,
        coalesce(a.AnswerCount, 0) as TotalAnswers,
        coalesce(avg_ans.Score, 0) as AvgAnswerScore,
        max_ans.Score as MaxAnswerScore,
        stragg.AnswerOwners
    from TopQuestionsPerUser q
    left join (
        select ParentId, count(*) AnswerCount
        from Posts where PostTypeId = 2
        group by ParentId
    ) a on q.PostId = a.ParentId
    left join (
        select ParentId, avg(cast(Score as numeric)) as Score
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) avg_ans on q.PostId = avg_ans.ParentId
    left join (
        select ParentId, max(Score) as Score
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) max_ans on q.PostId = max_ans.ParentId
    left join (
        select 
            ParentId, 
            string_agg(concat(u.DisplayName, '(', p.Score, ')'), ', ' order by p.Score desc) as AnswerOwners
        from Posts p
        left join Users u on p.OwnerUserId = u.Id
        where p.PostTypeId = 2
        group by ParentId
    ) stragg on q.PostId = stragg.ParentId
), BadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
), UserScores as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        case 
            when u.Reputation = 0 then NULL
            else (cast(bc.GoldBadges as float) * 5 + bc.SilverBadges * 3 + bc.BronzeBadges) / u.Reputation
        end as BadgeScoreRatio
    from Users u
    left join BadgeCounts bc on u.Id = bc.UserId
), CloseVotesAgg as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVoteCount,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVoteCount,
        max(ph.CreationDate) as LastCloseOrReopen
    from PostHistory ph
    group by ph.PostId
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name ilike '%Duplicate%'
), ComplexStringFilteredTags as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        CASE 
            WHEN t.TagName ~* '^[a-z]+(-[a-z]+)*$' THEN 'Hyphenated Lowercase' 
            WHEN t.TagName ~* '^[A-Z]+$' THEN 'AllCaps' 
            ELSE 'Other'
        END as TagPattern,
        length(t.TagName) as TagLength,
        coalesce(tp.Name, 'Unknown') as TagPostType
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    left join PostTypes tp on p.PostTypeId = tp.Id
    where t.Count > 10
), FinalSelected as (
    select 
        q.QuestionId,
        q.QuestionScore,
        q.TotalAnswers,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.AnswerOwners,
        cs.DisplayName as OwnerName,
        cs.Reputation,
        cs.GoldBadges,
        cs.SilverBadges,
        cs.BronzeBadges,
        cs.BadgeScoreRatio,
        cv.CloseVoteCount,
        cv.ReopenVoteCount,
        cv.LastCloseOrReopen,
        coalesce(dl.RelatedPostId, -1) as DuplicateOfPostId,
        tft.TagName,
        tft.TagPattern,
        tft.TagLength,
        tft.TagPostType,
        -- complex predicate: weighted score with null fallback and logarithmic scaling
        case when q.QuestionScore is null then null
            else ln(abs(q.QuestionScore) + 2) * 
                 (coalesce(cv.CloseVoteCount, 0) + 1) / 
                 nullif((cs.Reputation + 100)::float, 0)
        end as WeightedComplexScore,
        -- window function: rank questions by weighted complex score within tag pattern
        rank() over (partition by tft.TagPattern order by 
            case when q.QuestionScore is null then 0 else q.QuestionScore end desc
        ) as RankWithinTagPattern
    from QuestionAnswerStats q
    left join Users cs on cs.Id = (select OwnerUserId from Posts where Id = q.QuestionId)
    left join UserScores cs on cs.UserId = cs.Id
    left join CloseVotesAgg cv on q.QuestionId = cv.PostId
    left join DuplicateLinks dl on q.QuestionId = dl.PostId
    left join Posts p2 on p2.Id = q.QuestionId
    left join ComplexStringFilteredTags tft on position(concat('<', tft.TagName, '>') in coalesce(p2.Tags, '')) > 0
    where q.TotalAnswers > 0
    and RankWithinTagPattern <= 10
)
select * from FinalSelected
order by WeightedComplexScore desc nulls last, QuestionScore desc
limit 100;