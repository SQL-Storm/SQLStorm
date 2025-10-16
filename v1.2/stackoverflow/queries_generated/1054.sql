-- {"query": "1054.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1566} 
with RecursivePosts as (
    select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
           p.AcceptedAnswerId, p.ParentId, p.Title,
           1 as Level,
           cast('' as varchar(4000)) as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
      and p.CreationDate > current_date - interval '1 year' -- recent questions
      and p.Score > 5 -- only well scored questions
    union all
    select c.Id, c.PostTypeId, c.CreationDate, c.Score, c.ViewCount, c.OwnerUserId,
           c.AcceptedAnswerId, c.ParentId, c.Title,
           rp.Level + 1,
           rp.Path || '->' || cast(c.Id as varchar)
    from Posts c
    inner join RecursivePosts rp on c.ParentId = rp.Id
    where c.PostTypeId = 2 -- answers
      and c.Score >= 0
      and rp.Level < 3
),
UserBadgeCtr as (
    select UserId,
           count(*) filter (where Class = 1) as GoldBadges,
           count(*) filter (where Class = 2) as SilverBadges,
           count(*) filter (where Class = 3) as BronzeBadges,
           sum(case when TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Badges
    group by UserId
),
UserActivity as (
    select u.Id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.Location,
           coalesce(u.Views, 0) as Views,
           coalesce(u.UpVotes, 0) as UpVotes,
           coalesce(u.DownVotes, 0) as DownVotes,
           ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TagBasedBadges,
           dense_rank() over (order by u.Reputation desc) as RankByReputation,
           row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as LocationRepRank
    from Users u
    left join UserBadgeCtr ub on ub.UserId = u.Id
),
PostScoreWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as NextScore,
        avg(p.Score) over (partition by p.PostTypeId) as AvgScoreType,
        stddev_samp(p.Score) over (partition by p.PostTypeId) as StdDevScoreType
    from Posts p
    where p.PostTypeId in (1,2) -- questions and answers
      and p.CreationDate > current_date - interval '2 years'
),
PostWithLinksAndComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        count(distinct pl.Id) filter (where pl.LinkTypeId = 1) as CountLinksLinked,
        count(distinct pl.Id) filter (where pl.LinkTypeId = 3) as CountLinksDuplicate,
        count(distinct c.Id) as CommentCount,
        bool_or(c.UserId is null) as HasAnonymousComment,
        max(c.CreationDate) as LastCommentDate
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    group by p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.Tags, p.OwnerUserId
),
RecentCloseVotes as (
    select ph.PostId, ph.Comment as CloseReasonId, crt.Name as CloseReasonName,
           ph.CreationDate, ph.UserId
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
      and ph.CreationDate > current_date - interval '6 months'
),
ActiveUsersPosts as (
    select ua.Id as UserId,
           ua.DisplayName, ua.Reputation,
           count(distinct p.Id) as TotalPosts,
           count(distinct case when p.PostTypeId = 1 then p.Id else null end) as QuestionsCount,
           count(distinct case when p.PostTypeId = 2 then p.Id else null end) as AnswersCount,
           avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
           avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
           max(p.ViewCount) filter (where p.PostTypeId = 1) as MaxQuestionViews
    from UserActivity ua
    left join Posts p on p.OwnerUserId = ua.Id
    where ua.Reputation > 1000
    group by ua.Id, ua.DisplayName, ua.Reputation
)
select distinct
    rp.Id as PostId,
    rp.Level,
    rp.Path,
    ptl.PostTypeName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    p.Title,
    ua.DisplayName as OwnerDisplayName,
    ua.Reputation as OwnerReputation,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TagBasedBadges,
    psl.PrevScore,
    psl.NextScore,
    psl.AvgScoreType,
    psl.StdDevScoreType,
    pl.CommentsCount,
    pl.CountLinksLinked,
    pl.CountLinksDuplicate,
    case when rcv.CloseReasonName is not null then rcv.CloseReasonName else 'Open' end as CloseStatus,
    ua.Location,
    ua.RankByReputation,
    ua.LocationRepRank,
    (select coalesce(string_agg(distinct t.TagName, ','), '') from Tags t
     where ('<'+t.TagName+'>' = any(string_to_array(rp.Tags, '><'))
           or rp.Tags like '%<' || t.TagName || '>%')) as TagList,
    case
        when ua.Reputation > 20000 then 'Expert'
        when ua.Reputation > 5000 then 'Intermediate'
        else 'Novice'
    end as UserLevel
from RecursivePosts rp
join PostTypes ptl on ptl.Id = rp.PostTypeId
left join Posts p on p.Id = rp.Id
left join UserActivity ua on ua.Id = rp.OwnerUserId
left join UserBadgeCtr ub on ub.UserId = rp.OwnerUserId
left join PostScoreWindow psl on psl.Id = rp.Id
left join PostWithLinksAndComments pl on pl.Id = rp.Id
left join RecentCloseVotes rcv on rcv.PostId = rp.Id
where rp.Level <= 3
  and ( pl.CommentCount > 1 or rp.Score > 10 )
order by ua.RankByReputation, rp.CreationDate desc
limit 100;