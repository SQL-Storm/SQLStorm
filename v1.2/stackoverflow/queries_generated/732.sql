-- {"query": "732.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1541} 
with RecursiveTagCounts as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.ViewCount,0) as PostViewCount,
        coalesce(p.Score,0) as PostScore,
        row_number() over (partition by t.Id order by p.CreationDate desc nulls last) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
),
FilteredTags as (
    select 
        Id, TagName, Count, PostViewCount, PostScore
    from RecursiveTagCounts
    where rn = 1
),
UserBadgeStats as (
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
PostVoteStats as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as TotalBounty,
        max(v.CreationDate) as LastVoteDate
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
),
TopAnswerers as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(a.Id) as AnswerCount,
        sum(a.Score) as TotalAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        row_number() over (order by sum(a.Score) desc) as Ranking
    from Users u
    join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id, u.DisplayName
    having count(a.Id) > 10
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
ClosedQuestionsWithReasons as (
    select 
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then crt.Name else null end) as CloseReason,
        min(ph.CreationDate) as ClosedDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    group by ph.PostId
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as Questions,
        count(p.Id) filter (where p.PostTypeId = 2) as Answers,
        count(c.Id) as Comments,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc nulls last) as LastActiveRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    t.TagName,
    t.Count as TagUsageCount,
    t.PostViewCount,
    t.PostScore,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TagBasedBadges,
    tvs.UpVotes,
    tvs.DownVotes,
    tvs.TotalBounty,
    ta.AnswerCount,
    ta.TotalAnswerScore,
    ta.AvgAnswerScore,
    ta.MaxAnswerScore,
    ta.MinAnswerScore,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.QuestionCreationDate,
    qas.QuestionScore,
    qas.AnswerId,
    qas.AnswerScore,
    qas.AnswerOwnerUserId,
    qas.AnswerOwnerDisplayName,
    cqwr.CloseReason,
    cqwr.ClosedDate,
    dup.PostId as DuplicatePostId,
    dup.RelatedPostId as DuplicateOfPostId,
    dup.PostTitle,
    dup.RelatedPostTitle,
    uaw.Questions as UserQuestions,
    uaw.Answers as UserAnswers,
    uaw.Comments as UserComments
from FilteredTags t
left join UserBadgeStats us on us.UserId = (
    select OwnerUserId from Posts where Tags like concat('%<', t.TagName, '>%') and OwnerUserId is not null limit 1
)
left join PostVoteStats tvs on tvs.PostId = (
    select Id from Posts where Tags like concat('%<', t.TagName, '>%') and PostTypeId = 1 order by Score desc limit 1
)
left join TopAnswerers ta on ta.UserId = us.UserId
left join QuestionAnswerStats qas on qas.QuestionId = (
    select Id from Posts where Tags like concat('%<', t.TagName, '>%') and PostTypeId = 1 order by CreationDate desc limit 1
)
left join ClosedQuestionsWithReasons cqwr on cqwr.PostId = qas.QuestionId
left join DuplicateLinks dup on dup.PostId = qas.QuestionId
left join UserActivityWindow uaw on uaw.UserId = us.UserId
where t.Count > 1000 and (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 5
order by t.Count desc, ta.TotalAnswerScore desc nulls last
limit 50;