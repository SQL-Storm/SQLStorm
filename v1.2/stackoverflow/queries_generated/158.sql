-- {"query": "158.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1387} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2)::int as UpVotes,
        sum(v.VoteTypeId = 3)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title, p.AcceptedAnswerId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerName,
        p.Title as RelatedTitle
    from PostLinks pl
    join Posts p on p.Id = pl.RelatedPostId
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
    where pl.LinkTypeId = 3
),
QuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AnswerUpVotes
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
ComplexUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(pv.TotalPosts, 0) as TotalPosts,
        coalesce(pv.TotalScore, 0) as TotalPostScore,
        coalesce(badges.GoldBadges, 0) as GoldBadges,
        coalesce(badges.SilverBadges, 0) as SilverBadges,
        coalesce(badges.BronzeBadges, 0) as BronzeBadges,
        coalesce(badges.TagBasedBadges, 0) as TagBasedBadges,
        case when u.LastAccessDate > now() - interval '30 days' then 1 else 0 end as ActiveLast30Days,
        case when u.Location is null or trim(u.Location) = '' then 'Unknown' else u.Location end as UserLocation,
        length(coalesce(u.AboutMe, '')) as AboutMeLength,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join (
        select OwnerUserId, count(*) as TotalPosts, sum(Score) as TotalScore
        from Posts
        group by OwnerUserId
    ) pv on pv.OwnerUserId = u.Id
    left join UserBadgeStats badges on badges.UserId = u.Id
)
select
    cts.TagRank,
    cts.TagName,
    cts.Count as TagUsageCount,
    cts.AnswerCount,
    cts.ViewCount,
    cts.Score as TagExcerptScore,
    dus.QuestionId,
    dus.Title as QuestionTitle,
    dus.QuestionScore,
    dus.AnswerId,
    dus.AnswerScore,
    dus.AnswerOwnerName,
    dus.AnswerCommentCount,
    dus.AnswerUpVotes,
    dup.RelatedPostId as DuplicateOf,
    dup.RelatedTitle as DuplicateTitle,
    dup.OwnerName as DuplicateOwner,
    cus.DisplayName as UserDisplayName,
    cus.Reputation,
    cus.TotalPosts,
    cus.TotalPostScore,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.TagBasedBadges,
    cus.ActiveLast30Days,
    cus.UserLocation,
    cus.AboutMeLength
from RecursiveTagCounts cts
left join QuestionsWithAcceptedAnswers dus on dus.QuestionId = (
    select p.Id from Posts p
    where p.PostTypeId = 1
      and p.Tags like concat('%<', cts.TagName, '>%')
    order by p.Score desc nulls last
    limit 1
)
left join DuplicateLinks dup on dup.PostId = dus.QuestionId
left join ComplexUserStats cus on cus.Id = dus.AnswerOwnerId
where cts.TagRank <= 50
order by cts.TagRank, dus.QuestionScore desc nulls last;