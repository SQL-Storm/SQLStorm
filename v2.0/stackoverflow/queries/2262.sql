-- {"query": "2262.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1080}
with RecursiveQuestions as (
    select 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered & Accepted'
            when p.AnswerCount > 0 then 'Answered'
            else 'Open'
        end as Status,
        coalesce(u.Reputation,0) as OwnerReputation,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as OwnerTopPostRank
    from 
        Posts p 
        left join Users u on p.OwnerUserId = u.Id
    where 
        p.PostTypeId = 1
        and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
BadgesAgg as (
    select 
        UserId,
        count(case when Class = 1 then 1 end) as GoldBadges,
        count(case when Class = 2 then 1 end) as SilverBadges,
        count(case when Class = 3 then 1 end) as BronzeBadges,
        count(distinct TagBased) as BadgeTagBasedTypes
    from Badges
    group by UserId
),
AnswerStats as (
    select 
        pa.ParentId as QuestionId,
        count(pa.Id) as TotalAnswers,
        avg(pa.Score) as AvgAnswerScore,
        max(pa.Score) as MaxAnswerScore,
        sum(case when pa.OwnerUserId is not null and bu.UserId = pa.OwnerUserId then 1 else 0 end) filter (where pa.Score > 0) as AnswersByBadgeOwners
    from 
        Posts pa
        left join BadgesAgg bu on pa.OwnerUserId = bu.UserId
    where 
        pa.PostTypeId = 2
    group by pa.ParentId
),
CloseReasonCounts as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotesCount
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
WindowTaggedQuestions as (
    select
        rq.Id,
        rq.Title,
        rq.Tags,
        array_length(string_to_array(substring(rq.Tags from 2 for char_length(rq.Tags)-2), '><'), 1) as TagCount,
        avg(rq.Score) over (partition by rq.OwnerUserId) as AvgScoreByOwner,
        sum(rq.ViewCount) over (partition by rq.OwnerUserId) as SumViewsByOwner,
        count(*) over (partition by rq.OwnerUserId) as PostsByOwner,
        rq.CreationDate,
        case 
            when rq.ClosedDate is not null then 'Closed'
            when rq.AcceptedAnswerId is not null then 'Answered & Accepted'
            when rq.AnswerCount > 0 then 'Answered'
            else 'Open'
        end as Status
    from 
        Posts rq
    where 
        rq.PostTypeId = 1 and rq.Tags is not null
)
select 
    rq.Id as QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.Status,
    rq.OwnerUserId,
    coalesce(b.GoldBadges,0) as OwnerGoldBadges,
    coalesce(b.SilverBadges,0) as OwnerSilverBadges,
    coalesce(b.BronzeBadges,0) as OwnerBronzeBadges,
    coalesce(b.BadgeTagBasedTypes,0) as BadgeTagBasedTypes,
    a.TotalAnswers,
    a.AvgAnswerScore,
    a.MaxAnswerScore,
    a.AnswersByBadgeOwners,
    crc.CloseReason,
    crc.CloseVotesCount,
    wq.TagCount,
    wq.AvgScoreByOwner,
    wq.SumViewsByOwner,
    wq.PostsByOwner,
    concat_ws(' | ',
        nullif(rq.Title, ''),
        'Tags:' || coalesce(cast(wq.TagCount as varchar), '?'),
        'Status:' || rq.Status,
        'Answers:' || coalesce(cast(a.TotalAnswers as varchar), '0'),
        'OwnerRep:' || coalesce(cast(rq.OwnerReputation as varchar), '0'),
        'GoldBadges:' || coalesce(cast(b.GoldBadges as varchar), '0')
    ) as SummaryText
from 
    RecursiveQuestions rq
    left join BadgesAgg b on rq.OwnerUserId = b.UserId
    left join AnswerStats a on a.QuestionId = rq.Id
    left join CloseReasonCounts crc on crc.PostId = rq.Id
    left join WindowTaggedQuestions wq on wq.Id = rq.Id
where 
    rq.Score > (select percentile_cont(0.95) within group (order by Score) from Posts where PostTypeId = 1)
    and (crc.CloseVotesCount is null or crc.CloseVotesCount < 5)
order by rq.Score desc, rq.ViewCount desc
limit 100;