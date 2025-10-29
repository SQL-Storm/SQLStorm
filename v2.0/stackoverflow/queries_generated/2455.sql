-- {"query": "2455.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1571} 
with RecursiveCTE as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        1 as Level,
        cast(p.Id as varchar) as Path
    from Posts p
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null

    union all

    select
        a.Id as PostId,
        a.PostTypeId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        a.ViewCount,
        a.Title,
        a.Tags,
        a.AcceptedAnswerId,
        r.Level + 1 as Level,
        r.Path || '->' || cast(a.Id as varchar)
    from Posts a
    join RecursiveCTE r on a.ParentId = r.PostId
    where a.PostTypeId = 2
), 

UserScores AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(vote_agg.UpVotes),0) as TotalUserUpVotes,
        coalesce(sum(vote_agg.DownVotes),0) as TotalUserDownVotes,
        avg(case when p.PostTypeId = 1 then p.Score else null end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score else null end) as AvgAnswerScore,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) as HighestBadgeClass,
        max(b.Date) filter (where b.Class = 1) as LastGoldBadgeDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select 
            PostId, 
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) vote_agg on vote_agg.PostId = p.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),

PostWithRank AS (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as ScoreRank,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecencyRank,
        case 
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed
    from Posts p
    where p.PostTypeId = 1
),

TopScoringPosts AS (
    select 
        pwr.Id,
        pwr.Title,
        pwr.Score,
        pwr.ViewCount,
        pwr.Tags,
        pwr.OwnerUserId,
        pwr.ScoreRank,
        pwr.RecencyRank,
        pwr.IsClosed,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        us.BadgeCount,
        us.HighestBadgeClass,
        us.LastGoldBadgeDate
    from PostWithRank pwr
    join Users u on u.Id = pwr.OwnerUserId
    left join UserScores us on us.UserId = u.Id
    where pwr.ScoreRank <= 5 and pwr.IsClosed = 0
),

Duplicates AS (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p.Title as RelatedTitle,
        p.Score as RelatedScore
    from PostLinks pl 
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),

TagAggregates AS (
    select
        unnest(string_to_array(substring(Tags from 2 for length(Tags)-2), '><')) as Tag,
        count(*) as TagCount,
        avg(Score) as AvgScore,
        avg(ViewCount) as AvgViewCount
    from Posts
    where PostTypeId = 1 and Tags is not null
    group by Tag
    having count(*) > 50
),

FinalResults AS (
    select
        tsp.Id as QuestionId,
        tsp.Title,
        substring(tsp.Tags from 2 for length(tsp.Tags)-2) as ParsedTags,
        tsp.Score,
        tsp.ViewCount,
        tsp.OwnerUserId,
        tsp.OwnerName,
        tsp.OwnerReputation,
        tsp.BadgeCount,
        tsp.HighestBadgeClass,
        tsp.LastGoldBadgeDate,
        da.Tag,
        da.TagCount,
        da.AvgScore as TagAvgScore,
        da.AvgViewCount as TagAvgViewCount,
        dup.RelatedPostId as DuplicateQuestionId,
        dup.RelatedTitle as DuplicateQuestionTitle,
        dup.RelatedScore as DuplicateQuestionScore
    from TopScoringPosts tsp
    left join TagAggregates da on position(da.Tag in tsp.Tags) > 0
    left join Duplicates dup on dup.PostId = tsp.Id
    where tsp.Score > 
    (
        select avg(Score) * 1.1 from Posts where PostTypeId = 1 and OwnerUserId = tsp.OwnerUserId
    )
)

select 
    fr.QuestionId,
    fr.Title,
    fr.ParsedTags,
    fr.Score,
    fr.ViewCount,
    fr.OwnerUserId,
    fr.OwnerName,
    fr.OwnerReputation,
    fr.BadgeCount,
    case fr.HighestBadgeClass 
        when 1 then 'Gold' 
        when 2 then 'Silver' 
        when 3 then 'Bronze'
        else null
    end as HighestBadge,
    fr.LastGoldBadgeDate,
    fr.Tag,
    fr.TagCount,
    round(fr.TagAvgScore::numeric, 2) as TagAvgScore,
    round(fr.TagAvgViewCount::numeric, 2) as TagAvgViewCount,
    fr.DuplicateQuestionId,
    fr.DuplicateQuestionTitle,
    fr.DuplicateQuestionScore,

    -- Complex calculation: Relative Score Adjusted by Owner Reputation and Tag Popularity
    round(
        (fr.Score::numeric / nullif(fr.TagAvgScore,0)) * log(nullif(fr.OwnerReputation,1)) * sqrt(nullif(fr.TagCount,1))
        ,4) as AdjustedScore,

    -- Window function: average score among all questions by this user
    avg(fr.Score) over (partition by fr.OwnerUserId) as AvgUserQuestionScore,

    -- String expression: Concatenate OwnerName with Tag and Duplicate Info (null-safe)
    coalesce(fr.OwnerName,'<unknown>') || ' | Tag: ' || coalesce(fr.Tag,'<none>') || 
    case when fr.DuplicateQuestionId is not null then ' | Duplicate of: ' || fr.DuplicateQuestionTitle else '' end as SummaryInfo
    
from FinalResults fr
order by AdjustedScore desc NULLS LAST, fr.Score desc
limit 100;