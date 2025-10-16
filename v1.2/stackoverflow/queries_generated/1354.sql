-- {"query": "1354.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1611} 
with recursive UserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        1 as depth,
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        array[]::int[] as AncestorPostIds,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000

    union all

    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.depth + 1,
        p2.Id,
        p2.PostTypeId,
        p2.Title,
        p2.Score,
        p2.ViewCount,
        ua.AncestorPostIds || p2.Id,
        ua.rn
    from UserActivity ua
    join Posts p2 on p2.ParentId = ua.PostId
    where ua.depth < 3
      and not p2.Id = any(ua.AncestorPostIds)
),

BadgesRanked AS (
    select
        UserId,
        Name,
        Class,
        TagBased,
        Date,
        rank() over (partition by UserId order by Date desc) as RankDesc
    from Badges
),

QuestionAnswerStats AS (
  select
      q.Id as QuestionId,
      q.OwnerUserId,
      q.Title,
      q.CreationDate as QuestionDate,
      q.Score as QuestionScore,
      q.ViewCount,
      count(a.Id) as AnswersCount,
      sum(case when a.Score is null then 0 else a.Score end) as AnswersScoreSum,
      max(a.Score) as MaxAnswerScore,
      bool_or(pl.LinkTypeId = 3) as HasDuplicateLink  -- 3= Duplicate link type
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3
  where q.PostTypeId = 1
  group by q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount
),

CloseVotesTrace AS (
  select ph.PostId,
         max(case when ph.PostHistoryTypeId = 10 then coalesce(c.Reason, 'Unknown') end) as CloseReason,
         max(ph.CreationDate) Filter (where ph.PostHistoryTypeId = 10) as CloseDate,
         max(ph.CreationDate) Filter (where ph.PostHistoryTypeId = 11) as ReopenDate,
         case 
           when max(ph.PostHistoryTypeId = 10::int)::int = 1 then true
           else false
         end as IsCurrentlyClosed
  from PostHistory ph
  left join CloseReasonTypes c on c.Id = cast(ph.Comment as int)
  group by ph.PostId
),

UserVotingPattern AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(v.Id) Filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(v.Id) Filter (where v.VoteTypeId = 3) as DownVotesCast,
        count(v.Id) Filter (where v.VoteTypeId = 5) as FavoritesCast,
        count(distinct v.PostId) as DistinctPostsVoted,
        coalesce(sum(v.BountyAmount), 0) as TotalBountyGiven
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),

WindowThoughtModel AS (
 select
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    count(c.Id) over (partition by p.Id) as CommentCountWindow,
    sum(vote_count) over (partition by p.OwnerUserId order by p.CreationDate / nullif(extract(epoch from p.CreationDate)::int,0)) as VotingMomentum
 from Posts p
 left join lateral (
    select count(*) as vote_count
    from Votes v2
    where v2.PostId = p.Id and v2.VoteTypeId = 2
 ) as votes_on_post on true
 left join Comments c on c.PostId = p.Id
 where p.PostTypeId in (1,2)
),

ComplexTagAggregation AS (
    select 
        t.TagName,
        t.Count,
        q.OwnerUserId,
        max(q.Score) as MaxQuestionScore,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswerCount,
        avg(length(coalesce(p.Body, ''))) as AverageBodyCharLength,
        regexp_replace(min(q.Tags), '[<>]', '', 'g') as CleanedTagList
    from Tags t 
    left join Posts q on q.PostTypeId = 1 and q.Tags like '%' || t.TagName || '%'
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Posts p on p.Id = q.Id
    group by t.TagName, t.Count, q.OwnerUserId
    having sum(case when a.Score > 0 then 1 else 0 end) > 5
),

BenchmarkingSetUnion AS (
    select UserId, displayname from Users where Reputation > 5000
    union
    select UserId, displayname from Badges where Class = 1
    intersect
    select UserId, displayname from UserVotingPattern where UpVotesCast > 200
)

select 
    UA.UserId,
    UA.DisplayName,
    UA->> ('depth') depth_level,
    QAS.QuestionId,
    QAS.Title as QuestionTitle,
    QAS.Score as QuestionScore,
    QAS.ViewCount as QuestionViews,
    COALESCE(BadgesRanked.RankDesc, 0) BadgeRank,
    BW.displayname as BenchmarkName,
    Case when CVT.IsCurrentlyClosed then CVT.CloseReason else 'Open' end as PostStatus,
    ETA.TagName as PopularTagName,
    ETA.PositiveAnswerCount,
    UVC.UpVotesCast,
    WindowThoughtModel.CommentCountWindow,
    WindowThoughtModel.VotingMomentum,
    regexp_replace(coalesce(QAS.Title, ''), '\s+',' ','g') as CleanedQuestionTitle,
    length(COALESCE(UA.DisplayName, '')) as DisplayNameLength,
    substring(COALESCE(UA.DisplayName,'') from '[A-Z]{2,}') as UpperWordsInDisplayName
from UserActivity UA
join QuestionAnswerStats QAS on QAS.OwnerUserId = UA.UserId
left join BadgesRanked on BadgesRanked.UserId = UA.UserId and BadgesRanked.RankDesc = 1
left join CloseVotesTrace CVT on CVT.PostId = QAS.QuestionId
left join ComplexTagAggregation ETA on ETA.OwnerUserId = UA.UserId
left join UserVotingPattern UVC on UVC.UserId = UA.UserId
left join BenchmarkingSetUnion BW on BW.UserId = UA.UserId
left join WindowThoughtModel on WindowThoughtModel.Id = QAS.QuestionId
where UA.rn <=3 and (CVT.IsCurrentlyClosed is null or CVT.IsCurrentlyClosed = false)
order by UA.UserId, QAS.Score desc
limit 100;