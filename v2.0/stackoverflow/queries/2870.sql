-- {"query": "2870.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1181}
with RecursiveTaggedQuestions as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.CreationDate,
        array_agg(distinct t.TagName) filter (where t.TagName is not null) as Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentRank
    from Posts p
    left join LATERAL (
      select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
    ) t on true
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 -- Question
    group by p.Id, p.Title, p.OwnerUserId, u.DisplayName, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount
), FilteredQuestions as (
    select * from RecursiveTaggedQuestions
    where Tags @> array['sql', 'performance'] 
      and Score > 5
      and RecentRank <= 5
), AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as TotalAnswers,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnswersWithOwner,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        bool_or(a.CreationDate > q.CreationDate + interval '7 days') as HasLateAnswer
    from Posts a
    join Posts q on q.Id = a.ParentId
    where a.PostTypeId = 2
    group by a.ParentId, q.CreationDate
), UserBadgeAgg as (
    select 
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges,
        bool_or(b.Class = 0) filter (where b.TagBased = true) as HasTagBadge
    from Badges b
    group by b.UserId
), CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = CAST(ph.Comment AS integer)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
), VotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
)
select
    fq.Id as QuestionId,
    fq.Title,
    fq.OwnerUserId,
    fq.OwnerName,
    fq.CreationDate,
    array_to_string(fq.Tags, ',') as TagList,
    fq.Score,
    fq.ViewCount,
    fq.AnswerCount,
    fq.FavoriteCount,
    coalesce(asl.TotalAnswers, 0) as TotalAnswers,
    coalesce(asl.AnswersWithOwner, 0) as AnswersWithOwners,
    coalesce(asl.MaxAnswerScore, 0) as MaxAnswerScore,
    round(coalesce(asl.AvgAnswerScore, 0),2) as AvgAnswerScore,
    asl.HasLateAnswer,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.TotalBadges,
    uba.HasTagBadge,
    crc.CloseReason,
    crc.CloseCount,
    vs.UpVotes,
    vs.DownVotes,
    vs.Favorites,
    (select c.Text from Comments c where c.PostId = fq.Id order by c.CreationDate desc limit 1) as LatestComment,
    sum(fq.ViewCount) over (partition by fq.OwnerUserId order by fq.CreationDate rows between unbounded preceding and current row) as RunningViewSum,
    case 
        when fq.Score is null or fq.ViewCount is null then null
        when fq.ViewCount = 0 then null
        else round((CAST(fq.Score AS numeric) / nullif(fq.ViewCount,0)) * 1000 + coalesce(fq.FavoriteCount,0) * 2, 2)
    end as PopularityIndex
from FilteredQuestions fq
left join AnswerStats asl on asl.QuestionId = fq.Id
left join UserBadgeAgg uba on uba.UserId = fq.OwnerUserId
left join CloseReasonCounts crc on crc.PostId = fq.Id and crc.CloseCount = (
    select max(CloseCount) 
    from CloseReasonCounts crc2 
    where crc2.PostId = fq.Id
)
left join VotesSummary vs on vs.PostId = fq.Id
where fq.OwnerUserId is not null
order by PopularityIndex desc nulls last, fq.CreationDate desc
limit 100;