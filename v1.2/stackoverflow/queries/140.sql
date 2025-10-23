-- {"query": "140.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1459} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVoteAggregates as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
PostWithHistory as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.Comment as HistoryComment
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.PostTypeId = 1
),
RankedPostHistory as (
    select
        ph.*,
        row_number() over (partition by ph.Id order by ph.HistoryDate desc nulls last) as rn
    from PostWithHistory ph
),
FilteredPostHistory as (
    select * from RankedPostHistory where rn = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        u.DisplayName as OwnerName,
        p.Title as RelatedTitle
    from PostLinks pl
    join Posts p on p.Id = pl.RelatedPostId
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
    where pl.LinkTypeId = 3
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as AnswersPosted,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as TotalScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
CorrelatedTopAnswerers as (
    select distinct
        p.OwnerUserId,
        u.DisplayName,
        p.ParentId as QuestionId,
        p.Score as AnswerScore
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 2
      and p.Score > (
          select avg(p2.Score) from Posts p2 where p2.ParentId = p.ParentId and p2.PostTypeId = 2
      )
),
CombinedResults as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        pa.UpVotes,
        pa.DownVotes,
        pa.TotalBounty,
        fa.AnswerScore,
        dt.RelatedPostId as DuplicateOf,
        dt.RelatedTitle as DuplicateTitle,
        rtc.TagName,
        rtc.Count as TagCount,
        rtc.AnswerCount,
        rtc.ViewCount,
        rtc.Score as TagScore
    from Users u
    left join UserBadgeStats ub on ub.UserId = u.Id
    left join PostVoteAggregates pa on pa.OwnerUserId = u.Id
    left join CorrelatedTopAnswerers fa on fa.OwnerUserId = u.Id
    left join DuplicateLinks dt on dt.PostId = (select min(Id) from Posts where OwnerUserId = u.Id)
    left join RecursiveTagCounts rtc on rtc.rn = 1
    where u.Reputation > 1000
)
select
    cr.UserId,
    cr.DisplayName,
    cr.Reputation,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.UpVotes,
    cr.DownVotes,
    cr.TotalBounty,
    coalesce(cr.AnswerScore, 0) as TopAnswerScore,
    cr.DuplicateOf,
    cr.DuplicateTitle,
    cr.TagName,
    cr.TagCount,
    cr.AnswerCount,
    cr.ViewCount,
    cr.TagScore,
    case
        when cr.GoldBadges > 10 then 'Elite'
        when cr.SilverBadges > 20 then 'Experienced'
        when cr.BronzeBadges > 50 then 'Active'
        else 'Newbie'
    end as UserLevel,
    concat(
        'User ', cr.DisplayName, ' has reputation ', cr.Reputation,
        ', badges (G/S/B): ', cr.GoldBadges, '/', cr.SilverBadges, '/', cr.BronzeBadges,
        ', votes (Up/Down): ', cr.UpVotes, '/', cr.DownVotes,
        ', bounty earned: ', coalesce(cr.TotalBounty,0),
        ', top answer score: ', coalesce(cr.AnswerScore,0),
        ', associated tag: ', coalesce(cr.TagName,'N/A'),
        ' (count: ', coalesce(cr.TagCount,0), ')'
    ) as Summary
from CombinedResults cr
where cr.UpVotes is not null
order by cr.Reputation desc, cr.GoldBadges desc, cr.TagScore desc
limit 100;