-- {"query": "393.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1648} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
),
UserBadgeAgg as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreStats as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserTopPostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title
),
AcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
ComplexUserSummary as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(uba.GoldBadges,0) as GoldBadges,
        coalesce(uba.SilverBadges,0) as SilverBadges,
        coalesce(uba.BronzeBadges,0) as BronzeBadges,
        ua.PostsLast30Days,
        ua.ScoreLast30Days,
        case when u.WebsiteUrl is not null and u.WebsiteUrl != '' then 1 else 0 end as HasWebsite,
        case when u.Location is not null and length(u.Location) > 0 then u.Location else 'Unknown' end as LocationNormalized,
        coalesce((select count(*) from Comments c where c.UserId = u.Id),0) as CommentCount,
        coalesce((select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2),0) as UserUpVotes
    from Users u
    left join UserBadgeAgg uba on uba.UserId = u.Id
    left join UserActivityWindow ua on ua.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges, ua.PostsLast30Days, ua.ScoreLast30Days, u.WebsiteUrl, u.Location
)
select
    cts.TagName,
    cts.Count as TagCount,
    cts.TotalAnswers,
    cts.TotalViews,
    avg(pss.Score) filter (where pss.PostTypeId = 1) as AvgQuestionScore,
    avg(pss.Score) filter (where pss.PostTypeId = 2) as AvgAnswerScore,
    max(pss.Score) filter (where pss.PostTypeId = 1) as MaxQuestionScore,
    max(pss.Score) filter (where pss.PostTypeId = 2) as MaxAnswerScore,
    crc.CloseReasonName,
    crc.CloseCount,
    dupl.PostTitle as DuplicatePostTitle,
    dupl.RelatedPostTitle as DuplicateRelatedPostTitle,
    cu.DisplayName as ActiveUser,
    cu.Reputation as ActiveUserReputation,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.PostsLast30Days,
    cu.ScoreLast30Days,
    cu.HasWebsite,
    cu.LocationNormalized,
    cu.CommentCount,
    cu.UserUpVotes,
    aad.AnswerId as AcceptedAnswerId,
    aad.AnswerScore as AcceptedAnswerScore,
    aad.AnswerOwnerName,
    aad.AnswerOwnerReputation,
    concat_ws(' | ',
        case when pss.Title is not null then substring(pss.Title from 1 for 50) else 'No Title' end,
        coalesce(pss.Tags, 'No Tags'),
        'Score: ' || coalesce(pss.Score::text, '0'),
        'Views: ' || coalesce(pss.ViewCount::text, '0')
    ) as PostSummary
from RecursiveTagCounts cts
left join PostScoreStats pss on pss.Tags like concat('%<', cts.TagName, '>%')
left join CloseReasonCounts crc on crc.CloseReasonId = '101' -- example: duplicate close reason
left join DuplicateLinks dupl on dupl.PostId = pss.Id
left join ComplexUserSummary cu on cu.Id = pss.OwnerUserId
left join AcceptedAnswerDetails aad on aad.QuestionId = pss.Id
where cts.rn = 1
  and (pss.Score > 10 or pss.ViewCount > 1000 or pss.PostTypeId = 1)
order by cts.Count desc, AvgQuestionScore desc
limit 50;