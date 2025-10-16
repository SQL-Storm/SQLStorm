-- {"query": "4086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1754} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        cast(t.TagName as varchar(350)) as FullHierarchy,
        1 as Level
    from Tags t
    where t.IsRequired = 1

    union all

    select 
        child.Id,
        child.TagName,
        child.Count,
        child.IsModeratorOnly,
        child.IsRequired,
        cast(parent.FullHierarchy || '>' || child.TagName as varchar(350)),
        parent.Level + 1
    from Tags child
    join PostLinks pl on pl.PostId = child.ExcerptPostId
    join RecursiveTagHierarchy parent on pl.RelatedPostId = parent.ExcerptPostId
    where child.Id <> parent.Id and child.IsRequired = 1 and parent.Level < 3
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as QuestionCount,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as AnswerCount,
        coalesce(avg(p.Score),0) filter (where p.PostTypeId in (1,2)) as AvgScore,
        max(p.CreationDate) as LastPostDate,
        max(case when p.PostTypeId = 1 then p.Id end) as LatestQuestionId
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionWithAcceptedAnswer as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.Score as QuestionScore,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerId
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
),
BadgeSummaryByUser as (
    select 
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        count(distinct case when TagBased = 1 then Name end) as TagBasedBadgesCount,
        count(distinct case when TagBased = 0 then Name end) as NamedBadgesCount
    from Badges
    group by UserId
),
UserVoteBehavior as (
    select 
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesMade,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesMade,
        count(distinct v.PostId) as DistinctPostsVotedOn,
        count(*) as TotalVotesMade,
        coalesce(avg(p.Score),0) as AvgScoreOfVotedPosts
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    left join Posts p on p.Id = v.PostId
    where v.UserId is not null
    group by v.UserId
),
RecentPostEdits as (
    select 
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        count(*) as EditCount,
        max(case when ph.PostHistoryTypeId in (10,11) then ph.Comment end) as LastCloseReason
    from PostHistory ph
    group by ph.PostId
),
TopQuestionsWithContexts as (
    select 
        q.QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.QuestionScore,
        q.AcceptedAnswerId,
        q.AcceptedAnswerScore,
        q.AcceptedAnswerOwnerId,
        u.DisplayName as QuestionOwner,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        u.Reputation as OwnerReputation,
        COALESCE(comments.CommentCount, 0) as TotalComments,
        COALESCE(edits.EditCount,0) as EditCount,
        COALESCE(edits.LastEditDate, q.CreationDate) as LastEditDate,
        case
            when edits.LastCloseReason is not null then edits.LastCloseReason
            else 'Open'
        end as CloseStatus
    from QuestionWithAcceptedAnswer q
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = q.QuestionId)
    left join BadgeSummaryByUser b on b.UserId = u.Id
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) comments on comments.PostId = q.QuestionId
    left join RecentPostEdits edits on edits.PostId = q.QuestionId
    where q.Score > 10
    order by q.QuestionScore desc
    limit 100
)
select 
    tq.QuestionId,
    tq.Title,
    tq.Tags,
    substring(tq.Title from 1 for 100) || '...' as TitleSnippet,
    tq.CreationDate,
    tq.QuestionScore,
    tq.AcceptedAnswerId,
    tq.AcceptedAnswerScore,
    tq.AcceptedAnswerOwnerId,
    tq.QuestionOwner,
    tq.OwnerReputation,
    tq.GoldBadges,
    tq.SilverBadges,
    tq.BronzeBadges,
    tq.TotalComments,
    tq.EditCount,
    tq.LastEditDate,
    tq.CloseStatus,
    uch.Level,
    uch.FullHierarchy,
    us.AvgScore as OwnerAvgPostScore,
    uvb.UpVotesMade,
    uvb.DownVotesMade,
    uvb.DistinctPostsVotedOn,
    uvb.TotalVotesMade,
    uvb.AvgScoreOfVotedPosts,
    -- Correlated subquery to get highest scoring answer for a given question excluding accepted answer
    (select max(a.Score) from Posts a where a.ParentId = tq.QuestionId and a.Id <> tq.AcceptedAnswerId) as HighestOtherAnswerScore,
    -- Window function to rank questions per day by Score
    rank() over (partition by date(tq.CreationDate) order by tq.QuestionScore desc) as DailyRank
from TopQuestionsWithContexts tq
left join RecursiveTagHierarchy uch on position(uch.TagName in coalesce(tq.Tags,'')) > 0
left join UserPostStats us on us.UserId = (select OwnerUserId from Posts where Id = tq.QuestionId)
left join UserVoteBehavior uvb on uvb.UserId = (select OwnerUserId from Posts where Id = tq.QuestionId)
where 
    (tq.CloseStatus = 'Open' or tq.CloseStatus is null)
    and (uch.Level is null or uch.Level <=2)
union
select 
    p.Id as QuestionId,
    p.Title,
    p.Tags,
    substring(p.Title from 1 for 100) || '...' as TitleSnippet,
    p.CreationDate,
    p.Score as QuestionScore,
    null as AcceptedAnswerId,
    null as AcceptedAnswerScore,
    null as AcceptedAnswerOwnerId,
    u.DisplayName as QuestionOwner,
    u.Reputation as OwnerReputation,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TotalComments,
    0 as EditCount,
    p.CreationDate as LastEditDate,
    'Closed' as CloseStatus,
    null as Level,
    null as FullHierarchy,
    0 as OwnerAvgPostScore,
    0 as UpVotesMade,
    0 as DownVotesMade,
    0 as DistinctPostsVotedOn,
    0 as TotalVotesMade,
    0 as AvgScoreOfVotedPosts,
    null as HighestOtherAnswerScore,
    null as DailyRank
from Posts p
join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
and p.ClosedDate is not null
and p.Score > 50
order by QuestionScore desc, CreationDate desc
limit 50;