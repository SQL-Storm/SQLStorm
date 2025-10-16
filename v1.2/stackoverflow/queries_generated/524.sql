-- {"query": "524.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1540} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.OwnerUserId,
        p.Id as PostId,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    where p.PostTypeId = 1
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name,
        b.Class,
        dense_rank() over (partition by b.UserId order by b.Class) as BadgeRank
    from Badges b
),
TopUserBadges as (
    select
        UserId,
        array_agg(Name order by Class) filter (where BadgeRank = 1) as TopBadges
    from UserBadgeRanks
    group by UserId
),
PostVoteStats as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyClosed
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(acc.Score,0) as AcceptedAnswerScore,
        coalesce(pvs.UpVotes,0) as QuestionUpVotes,
        coalesce(pvs.DownVotes,0) as QuestionDownVotes,
        coalesce(pvs.BountyStarted,0) as QuestionBountyStarted,
        coalesce(pvs.BountyClosed,0) as QuestionBountyClosed
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on ans.ParentId = q.Id
    left join Posts acc on acc.Id = q.AcceptedAnswerId
    left join PostVoteStats pvs on pvs.PostId = q.Id
    where q.PostTypeId = 1
),
RankedUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct b.Id) as BadgesEarned,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on chtt.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by crt.Name
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
UserLatestActivity as (
    select
        u.Id as UserId,
        max(coalesce(p.LastActivityDate, c.CreationDate, ph.CreationDate)) as LatestActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
)
select
    qas.QuestionId,
    qas.Title,
    qas.OwnerUserId,
    u.DisplayName as QuestionOwner,
    qas.CreationDate,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.AcceptedAnswerScore,
    qas.QuestionUpVotes,
    qas.QuestionDownVotes,
    qas.QuestionBountyStarted,
    qas.QuestionBountyClosed,
    array_to_string(string_to_array(qas.Tags, '><'), ', ') as TagList,
    rac.DisplayName as TopAnswerer,
    rac.UserRank as TopAnswererRank,
    rac.Reputation as TopAnswererReputation,
    rac.AnswersPosted as TopAnswererAnswers,
    trc.CloseReason,
    cr.CloseCount,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as DuplicateRelatedTitle,
    ul.LatestActivity as QuestionOwnerLatestActivity,
    case
        when qas.QuestionScore > 0 and qas.AnswerCount > 5 then 'Hot Question'
        when qas.QuestionScore < 0 then 'Controversial'
        else 'Normal'
    end as QuestionCategory
from QuestionAnswerStats qas
left join LATERAL (
    select u2.DisplayName, ru.UserRank, ru.Reputation, ru.AnswersPosted
    from Posts p2
    join Users u2 on u2.Id = p2.OwnerUserId
    join RankedUserActivity ru on ru.UserId = u2.Id
    where p2.PostTypeId = 2 and p2.ParentId = qas.QuestionId
    order by p2.Score desc nulls last
    limit 1
) rac on true
left join CloseReasonCounts cr on cr.CloseReason = (
    select crt.Name
    from PostHistory ph2
    join CloseReasonTypes crt on crt.Id::varchar = ph2.Comment
    where ph2.PostId = qas.QuestionId and ph2.PostHistoryTypeId = 10
    order by ph2.CreationDate desc limit 1
)
left join DuplicateLinks dl on dl.PostId = qas.QuestionId
left join Users u on u.Id = qas.OwnerUserId
left join RankedUserActivity ru on ru.UserId = qas.OwnerUserId
left join UserLatestActivity ul on ul.UserId = qas.OwnerUserId
where qas.AnswerCount > 0
order by qas.QuestionScore desc nulls last, qas.ViewCount desc nulls last
limit 100;