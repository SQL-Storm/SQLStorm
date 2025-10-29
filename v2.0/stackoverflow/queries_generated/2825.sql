-- {"query": "2825.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1551} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as TotalViews,
        u.Reputation as OwnerReputation,
        u.DisplayName as OwnerDisplayName,
        p.Id as PostId,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as rn
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on p.OwnerUserId = u.Id
    where t.Id < 1000 -- restrict to some tags for testing
),
TopTagPosts as (
    select
        TagId,
        TagName,
        PostId,
        AnswerCount,
        TotalViews,
        OwnerReputation,
        OwnerDisplayName
    from RecursiveTagCounts
    where rn <= 5
),
LatestCloseReasons as (
    select distinct on (ph.PostId)
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate
    from PostHistory ph
    inner join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
),
UserBadgeSummary as (
    select
        b.UserId,
        u.DisplayName,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    inner join Users u on u.Id = b.UserId
    group by b.UserId, u.DisplayName
),
PostVoteAggregates as (
    select
        p.Id as PostId,
        p.PostTypeId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId
),
AnswerWithAcceptedFlag as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted
    from Posts a
    inner join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
),
AnswerRankings as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score,
        a.IsAccepted,
        rank() over (partition by a.ParentId order by a.Score desc, a.Id asc) as ScoreRank
    from AnswerWithAcceptedFlag a
),
FinalPostDetails as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        coalesce(pv.UpVotes, 0) as UpVotes,
        coalesce(pv.DownVotes, 0) as DownVotes,
        coalesce(pv.TotalBounty, 0) as TotalBounty,
        lcr.CloseReasonName,
        case
            when lcr.CloseReasonName is not null then true
            else false
        end as IsClosed,
        row_number() over (order by p.Score desc, p.ViewCount desc nulls last) as PopularityRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join UserBadgeSummary us on us.UserId = p.OwnerUserId
    left join PostVoteAggregates pv on pv.PostId = p.Id
    left join LatestCloseReasons lcr on lcr.PostId = p.Id
    where p.PostTypeId = 1
)
select fpd.Id as QuestionId,
       fpd.Title,
       fpd.CreationDate,
       fpd.Score,
       fpd.ViewCount,
       fpd.Tags,
       fpd.OwnerName,
       fpd.OwnerReputation,
       fpd.GoldBadges,
       fpd.SilverBadges,
       fpd.BronzeBadges,
       fpd.UpVotes,
       fpd.DownVotes,
       fpd.TotalBounty,
       fpd.IsClosed,
       fpd.CloseReasonName,
       coalesce(ans.AnswerCount, 0) as TotalAnswers,
       coalesce(accepted.AnswerId, 0) as AcceptedAnswerId,
       accepted.Score as AcceptedAnswerScore,
       top5.TopAnswers,
       ttp.TagName,
       ttp.OwnerDisplayName as TopAnswerOwner,
       ttp.OwnerReputation as TopAnswerOwnerReputation,
       ttp.AnswerCount as TagAnswerCount,
       ttp.TotalViews as TagViewCount
from FinalPostDetails fpd
left join (
    select ParentId, count(*) as AnswerCount
    from Posts
    where PostTypeId = 2
    group by ParentId
) ans on ans.ParentId = fpd.Id
left join AnswerRankings accepted on accepted.QuestionId = fpd.Id and accepted.IsAccepted = 1
left join (
    select
        a.ParentId,
        string_agg(format('AnswerId:%s Score:%s IsAccepted:%s', a.Id, a.Score, a.IsAccepted), '; ' order by a.Score desc) as TopAnswers
    from AnswerWithAcceptedFlag a
    group by a.ParentId
) top5 on top5.ParentId = fpd.Id
left join TopTagPosts ttp on ttp.PostId = fpd.Id
where fpd.PopularityRank <= 100
order by fpd.Score desc, fpd.ViewCount desc
union
select
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as UpVotes,
    0 as DownVotes,
    0 as TotalBounty,
    false as IsClosed,
    NULL as CloseReasonName,
    0 as TotalAnswers,
    NULL as AcceptedAnswerId,
    NULL as AcceptedAnswerScore,
    NULL as TopAnswers,
    NULL as TagName,
    NULL as TopAnswerOwner,
    NULL as TopAnswerOwnerReputation,
    0 as TagAnswerCount,
    0 as TagViewCount
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1 and p.Id not in (select Id from FinalPostDetails)
order by Score desc
limit 10;