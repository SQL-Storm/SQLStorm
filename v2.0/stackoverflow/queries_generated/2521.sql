-- {"query": "2521.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1285} 
with UserReputations as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) filter (where b.Class is not null) as HighestBadgeClass,
        row_number() over (order by u.Reputation desc, count(distinct b.Id) desc) as RepRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopQuestions as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        coalesce(p.Score,0) as Score,
        coalesce(p.ViewCount,0) as Views,
        p.CreationDate,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by coalesce(p.Score,0) desc) as QuestionRankPerUser
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
),
AnswersInfo as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        a.Body,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    left join Posts q on q.Id = a.ParentId
    where a.PostTypeId = 2 and a.OwnerUserId is not null
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 1 else 0 end) as AnonymousComments
    from Comments c
    group by c.PostId
),
AnswerVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'AcceptedByOriginator' then 1 else 0 end) as AcceptedVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserActivity as (
    select
        u.Id,
        count(distinct ph.PostId) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents,
        count(distinct ph.PostId) filter (where ph.PostHistoryTypeId = 12) as DeletedPosts,
        count(distinct ph.PostId) filter (where ph.PostHistoryTypeId = 13) as UndeletedPosts,
        count(distinct ph.PostId) filter (where ph.PostHistoryTypeId = 50) as CommunityBumps
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
),
QuestionsWithDuplicates as (
    select
        q.Id as QuestionId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where q.PostTypeId = 1
    group by q.Id
),
QuestionsCTE as (
    select
        tq.*,
        qc.CommentCount,
        qc.AnonymousComments,
        av.UpVotes,
        av.DownVotes,
        av.AcceptedVotes,
        qwd.DuplicateCount,
        u.Reputation as OwnerReputation,
        u.DisplayName as OwnerName,
        ua.CloseReopenEvents,
        ua.DeletedPosts,
        ua.UndeletedPosts,
        ua.CommunityBumps,
        u.ProfileImageUrl,
        dense_rank() over (order by coalesce(tq.Score,0) desc) as GlobalQuestionRank
    from TopQuestions tq
    left join QuestionComments qc on qc.PostId = tq.Id
    left join AnswerVotes av on av.PostId = tq.Id
    left join QuestionsWithDuplicates qwd on qwd.QuestionId = tq.Id
    left join Users u on u.Id = tq.OwnerUserId
    left join UserActivity ua on ua.Id = tq.OwnerUserId
)
select
    q.GlobalQuestionRank,
    q.Id as QuestionId,
    q.Title,
    q.Score,
    q.Views,
    q.CommentCount,
    q.AnonymousComments,
    q.UpVotes,
    q.DownVotes,
    q.AcceptedVotes,
    q.DuplicateCount,
    q.OwnerUserId,
    q.OwnerName,
    q.OwnerReputation,
    q.CloseReopenEvents,
    q.DeletedPosts,
    q.UndeletedPosts,
    q.CommunityBumps,
    q.ProfileImageUrl,
    uq.BadgeCount as OwnerBadgeCount,
    uq.HighestBadgeClass as OwnerHighestBadgeClass,
    round(
        100.0 * (q.UpVotes + 1) / nullif((q.DownVotes + 1), 0),
        2
    ) as UpDownRatio,
    substring(
        concat_ws(' ',
            q.Title,
            coalesce(cast(q.Views as varchar), ''),
            coalesce(cast(q.Score as varchar), ''),
            coalesce(cast(q.CommentCount as varchar), ''),
            q.OwnerName
        )
        from 1 for 100
    ) as SummarySnippet,
    case
        when q.DuplicateCount > 0 then 'Has duplicates'
        when q.DeletedPosts > 0 then 'Deleted activity'
        when q.CloseReopenEvents > 5 then 'High close/reopen activity'
        else 'Normal'
    end as StatusCategory
from QuestionsCTE q
left join UserReputations uq on uq.Id = q.OwnerUserId
where q.QuestionRankPerUser <= 3
  and q.OwnerReputation > (
    select avg(Reputation) from Users where Reputation is not null
  )
order by q.GlobalQuestionRank
limit 100;