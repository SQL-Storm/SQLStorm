-- {"query": "2285.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2011}
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by max(b.Date) desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsersByBadges as (
    select
        UserId,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges
    from RecursiveUserBadgeCounts
    where BadgeRank = 1
    order by GoldBadges desc, SilverBadges desc, BronzeBadges desc
    limit 100
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate as QuestionDate,
        p.OwnerUserId,
        p.Score as QuestionScore,
        p.ViewCount,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        coalesce(p.AcceptedAnswerId, 0) as AcceptedAnswerId
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.AcceptedAnswerId
),
UserLatestPosts as (
    select
        p.OwnerUserId,
        max(p.CreationDate) as LatestPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ua.LatestPostDate,
        count(p.Id) filter (where p.PostTypeId = 1 and p.CreationDate > cast('2024-10-01' as date) - interval '30 day') as RecentQuestions,
        count(p.Id) filter (where p.PostTypeId = 2 and p.CreationDate > cast('2024-10-01' as date) - interval '30 day') as RecentAnswers,
        sum(coalesce(p.Score,0)) filter (where p.PostTypeId in (1,2) and p.CreationDate > cast('2024-10-01' as date) - interval '30 day') as RecentPostScore,
        count(distinct c.Id) filter (where c.CreationDate > cast('2024-10-01' as date) - interval '30 day') as RecentComments
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join UserLatestPosts ua on ua.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ua.LatestPostDate
),
UserTopPosts as (
    select distinct on (p.OwnerUserId)
        p.OwnerUserId,
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate
    from Posts p
    where p.PostTypeId in (1,2)
    order by p.OwnerUserId, p.Score desc nulls last, p.ViewCount desc nulls last, p.CreationDate desc
),
UserAndQuestionStats as (
    select
        ua.Id as UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.RecentQuestions,
        ua.RecentAnswers,
        ua.RecentPostScore,
        ua.RecentComments,
        qas.QuestionId,
        qas.Title as QuestionTitle,
        qas.QuestionDate,
        qas.QuestionScore,
        qas.ViewCount as QuestionViews,
        qas.AnswerCount,
        qas.MaxAnswerScore,
        qas.AcceptedAnswerId
    from UserActivityWindow ua
    left join QuestionAnswerStats qas on qas.OwnerUserId = ua.Id
    where qas.QuestionDate > cast('2024-10-01' as date) - interval '60 day' or qas.QuestionId is null
),
PostLinksFiltered as (
    select
        pl.Id,
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pt.Name as LinkTypeName,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes pt on pt.Id = pl.LinkTypeId
    where pl.CreationDate > cast('2024-10-01' as date) - interval '30 day'
),
DuplicateQuestionsWithAnswers as (
    select
        pq.PostId as DuplicateQuestionId,
        pq.RelatedPostId as OriginalQuestionId,
        orig.Title as OriginalTitle,
        orig.CreationDate as OriginalCreationDate,
        dup.Title as DuplicateTitle,
        dup.CreationDate as DuplicateCreationDate,
        (select count(*) from Posts ans where ans.ParentId = pq.PostId and ans.PostTypeId = 2) as DuplicateAnswerCount
    from PostLinksFiltered pq
    join Posts orig on orig.Id = pq.RelatedPostId and orig.PostTypeId = 1
    join Posts dup on dup.Id = pq.PostId and dup.PostTypeId = 1
    where pq.LinkTypeId = 3
),
WindowedVotes as (
    select
        v.PostId,
        v.VoteTypeId,
        vt.Name as VoteTypeName,
        v.CreationDate,
        count(*) over (partition by v.PostId, v.VoteTypeId order by v.CreationDate rows between unbounded preceding and current row) as CumulativeVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.CreationDate > cast('2024-10-01' as date) - interval '90 day'
),
AggregatedPostVotes as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStartTotal,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyCloseTotal
    from Votes v
    group by v.PostId
),
FinalUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(up.RecentQuestions,0) as RecentQuestions,
        coalesce(up.RecentAnswers,0) as RecentAnswers,
        coalesce(up.RecentPostScore,0) as RecentPostScore,
        coalesce(up.RecentComments,0) as RecentComments,
        utp.PostId as TopPostId,
        utp.Title as TopPostTitle,
        utp.Score as TopPostScore,
        utp.ViewCount as TopPostViews,
        row_number() over (order by u.Reputation desc nulls last, coalesce(up.RecentPostScore,0) desc nulls last) as UserRank
    from Users u
    left join UserActivityWindow up on up.Id = u.Id
    left join UserTopPosts utp on utp.OwnerUserId = u.Id
)
select
    fua.Id as UserId,
    fua.DisplayName,
    fua.Reputation,
    fua.RecentQuestions,
    fua.RecentAnswers,
    fua.RecentPostScore,
    fua.RecentComments,
    fua.TopPostId,
    fua.TopPostTitle,
    fua.TopPostScore,
    fua.TopPostViews,
    dq.DuplicateQuestionId,
    dq.OriginalQuestionId,
    dq.OriginalTitle,
    dq.DuplicateTitle,
    dq.DuplicateAnswerCount,
    coalesce(apv.UpVotes,0) as UpVotes,
    coalesce(apv.DownVotes,0) as DownVotes,
    coalesce(apv.FavoriteVotes,0) as FavoriteVotes,
    coalesce(apv.BountyStartTotal,0) as BountyStartTotal,
    coalesce(apv.BountyCloseTotal,0) as BountyCloseTotal,
    case when coalesce(fua.RecentQuestions,0) > 0 and coalesce(apv.UpVotes,0) > coalesce(apv.DownVotes,0) then 'ActivePositive'
         when coalesce(fua.RecentQuestions,0) > 0 and coalesce(apv.UpVotes,0) <= coalesce(apv.DownVotes,0) then 'ActiveNegative'
         when coalesce(fua.RecentQuestions,0) = 0 then 'Inactive'
         else 'Unknown' end as UserActivityStatus,
    (
        coalesce(fua.TopPostTitle,'No Top Post')
        || ' | ' || 'Reputation: ' || fua.Reputation
        || ' | ' || 'Questions in 30d: ' || fua.RecentQuestions
        || ' | ' || 'Answers in 30d: ' || fua.RecentAnswers
    ) as UserSummary
from FinalUserActivity fua
left join DuplicateQuestionsWithAnswers dq on dq.DuplicateQuestionId = fua.TopPostId
left join AggregatedPostVotes apv on apv.PostId = fua.TopPostId
where fua.UserRank <= 50
order by fua.UserRank, coalesce(apv.UpVotes,0) desc nulls last, coalesce(apv.DownVotes,0) asc nulls last;