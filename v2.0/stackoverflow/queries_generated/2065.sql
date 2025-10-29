-- {"query": "2065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1514} 
with RecursiveTagCounts as (
    select t.Id, t.TagName, t.Count,
        row_number() over (order by t.Count desc, t.TagName) as rn
    from Tags t
    where t.Count > 1000
), 
TopUserBadges as (
    select b.UserId, b.Name, b.Class,
           row_number() over (partition by b.UserId order by b.Date asc) as rn
    from Badges b
    where b.Class = 1
), 
UserPostStats as (
    select u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as Questions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as Answers,
        avg(p.Score) filter (where p.Score is not null) as AvgPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
), 
QuestionActivity as (
    select p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
RankedQuestions as (
    select qa.*,
        nt.Count as TagGlobalCount,
        row_number() over (partition by qa.OwnerName order by qa.Score desc, qa.CreationDate desc) as OwnerRank,
        dense_rank() over (order by qa.ViewCount desc) as GlobalViewRank
    from QuestionActivity qa
    left join RecursiveTagCounts nt on position(concat('<', nt.TagName, '>') in coalesce(qa.Tags, ''))>0
    where qa.Score > 5
),
LinkedPostsInfo as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
),
AnswerStats as (
    select p.ParentId as QuestionId,
        count(p.Id) as AnswerCount,
        max(p.Score) as MaxAnswerScore,
        avg(p.Score) as AvgAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalAnswerUpVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 2
    group by p.ParentId
),
UserReputationBounds as (
    select 
        min(Reputation) as MinRep,
        max(Reputation) as MaxRep,
        percentile_cont(0.25) within group (order by Reputation) as Q1Rep,
        percentile_cont(0.5) within group (order by Reputation) as MedianRep,
        percentile_cont(0.75) within group (order by Reputation) as Q3Rep
    from Users
),
PostsWithHistory as (
    select p.Id as PostId,
        p.Title, p.CreationDate, p.Score,
        ph.PostHistoryTypeId, pht.Name as HistoryTypeName,
        ph.CreationDate as HistoryChangeDate,
        ph.UserDisplayName as EditorName,
        ph.Comment as HistoryComment
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    where ph.PostHistoryTypeId in (4,5,6,10,11) -- edits and closure events
),
RecentEditors as (
    select distinct ph.UserId, ph.UserDisplayName, count(*) as EditCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.UserId, ph.UserDisplayName
    having count(*) > 10
)
select rq.OwnerName, rq.Title, rq.Score, rq.ViewCount, rq.AnswerCount, rq.FavoriteCount,
    rq.CommentCount, rq.UpVotes, rq.DownVotes, rq.IsClosed, rq.HasAcceptedAnswer,
    rq.TagGlobalCount,
    asw.MaxAnswerScore, asw.AvgAnswerScore, asw.TotalAnswerUpVotes,
    lpi.LinkTypeName,
    ubs.MinRep, ubs.MaxRep, ubs.MedianRep,
    us.AvgPostScore, us.TotalPosts, us.Questions, us.Answers,
    rh.HistoryTypeName, rh.HistoryChangeDate, rh.EditorName,
    concat(
        case when rq.IsClosed = 1 then 'Closed: ' else 'Open: ' end,
        coalesce(rh.HistoryComment, 'No close reason')
    ) as StatusDetail,
    case 
      when rq.Score > 100 then 'High scoring question'
      when rq.Score between 50 and 100 then 'Moderate scoring question'
      else 'Low scoring question'
    end as ScoreCategory,
    case 
        when us.Reputation is null then 'Unknown reputation'
        when us.Reputation >= ubs.Q3Rep then 'High rep user'
        when us.Reputation >= ubs.MedianRep then 'Medium rep user'
        else 'Low rep user'
    end as UserReputationCategory
from RankedQuestions rq
left join AnswerStats asw on asw.QuestionId = rq.Id
left join LinkedPostsInfo lpi on lpi.PostId = rq.Id
left join UserPostStats us on us.UserId = rq.OwnerName::int -- cast may fail, otherwise join via Users display name not reliable
left join UserReputationBounds ubs on true
left join PostsWithHistory rh on rh.PostId = rq.Id and rh.HistoryChangeDate = (
    select max(ph2.CreationDate) from PostHistory ph2 where ph2.PostId = rq.Id
)
where rq.OwnerRank <= 3
union
select u.DisplayName, null, null, null, null, null,
    null, null, null, null,
    null, null, null, null,
    null, null, null,
    'Recent editor', null, null,
    'No question', 'No score category', 'No rep category'
from RecentEditors u
order by Score desc nulls last, ViewCount desc nulls last, rq.OwnerName nulls last
limit 100;