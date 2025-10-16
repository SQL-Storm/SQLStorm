-- {"query": "905.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1437} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        0 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.Id is not null
  union all
    select 
        t2.Id,
        t2.TagName,
        rth.Level + 1,
        rth.Path || t2.TagName
    from Tags t2
    join PostLinks pl on pl.PostId = t2.ExcerptPostId or pl.RelatedPostId = t2.ExcerptPostId
    join RecursiveTagHierarchy rth on 
        (pl.PostId = rth.Id or pl.RelatedPostId = rth.Id) 
        and not t2.TagName = any(rth.Path)
    where rth.Level < 3
),
UserBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
TopPostsWithComments as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
PostsWithAcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        a.CreationDate as AnswerCreationDate,
        a.Score - q.Score as ScoreDifference
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
UserVoteActivity as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCasted,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCasted,
        count(distinct v.PostId) as PostsVotedOn
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
),
PostHistoryCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
)
select 
    u.Id as UserId,
    u.DisplayName,
    up.QuestionCount,
    up.AnswerCount,
    ub.GoldBadgeCount,
    ub.SilverBadgeCount,
    ub.BronzeBadgeCount,
    up.TotalPostScore,
    coalesce(voteact.UpVotesCasted,0) as UpVotesCasted,
    coalesce(voteact.DownVotesCasted,0) as DownVotesCasted,
    coalesce(voteact.PostsVotedOn,0) as PostsVotedOn,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.QuestionScore,
    qas.AcceptedAnswerScore,
    qas.ScoreDifference,
    qas.AnswerOwnerName,
    qas.AnswerCreationDate,
    case 
        when qas.ScoreDifference > 0 then 'Answer scored higher'
        when qas.ScoreDifference < 0 then 'Question scored higher'
        else 'Scores are equal or no accepted answer'
    end as ScoreComparison,
    coalesce(ph.CloseReasonName, 'Not Closed') as LastCloseReason,
    ph.CreationDate as CloseDate,
    string_agg(distinct rth.TagName, ', ') as RecursiveTagsPath
from Users u
left join UserPostStats up on up.UserId = u.Id
left join UserBadgeCounts ubg on ubg.UserId = u.Id
left join (
    select 
        UserId,
        sum(case when Class=1 then BadgeCount else 0 end) as GoldBadgeCount,
        sum(case when Class=2 then BadgeCount else 0 end) as SilverBadgeCount,
        sum(case when Class=3 then BadgeCount else 0 end) as BronzeBadgeCount
    from UserBadgeCounts
    group by UserId
) ub on ub.UserId = u.Id
left join UserVoteActivity voteact on voteact.UserId = u.Id
left join lateral (
    select * from PostsWithAcceptedAnswerStats qas 
    where qas.AnswerOwnerId = u.Id 
    order by qas.AnswerCreationDate desc limit 1
) qas on true
left join lateral (
    select ph2.*
    from PostHistoryCloseReasons ph2
    where ph2.PostId = qas.QuestionId
    order by ph2.CreationDate desc limit 1
) ph on true
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(qas.Title,''), ' '))
where u.Reputation > 1000
group by u.Id, u.DisplayName, up.QuestionCount, up.AnswerCount, ub.GoldBadgeCount, ub.SilverBadgeCount, ub.BronzeBadgeCount, up.TotalPostScore, voteact.UpVotesCasted, voteact.DownVotesCasted, voteact.PostsVotedOn, qas.QuestionId, qas.Title, qas.QuestionScore, qas.AcceptedAnswerScore, qas.ScoreDifference, qas.AnswerOwnerName, qas.AnswerCreationDate, ph.CloseReasonName, ph.CreationDate
order by up.TotalPostScore desc
limit 100;