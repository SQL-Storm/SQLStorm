-- {"query": "1447.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1881} 
with RecursiveBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.Class
),
LatestPostWithActivity as (
    select p1.Id, p1.OwnerUserId, p1.Title, p1.Score, p1.CreationDate, p1.LastActivityDate,
           row_number() over (partition by p1.OwnerUserId order by p1.LastActivityDate desc nulls last) as rn
    from Posts p1
    where p1.PostTypeId in (1, 2) -- questions and answers only
),
UserAvgPostScore as (
    select OwnerUserId, avg(cast(Score as float)) as AvgPostScore, count(*) as PostCount
    from Posts
    where Score is not null and PostTypeId in (1, 2)
    group by OwnerUserId
),
CloseCounts as (
    select OwnerUserId,
           sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseCount,
           sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.OwnerUserId is not null
    group by OwnerUserId
),
TopTagUsage as (
    select
        substring(t.TagName from 1 for 15) as ShortTagName,
        count(distinct pt.Id) as QCount,
        avg(coalesce(pt.Score, 0)) as AvgScore
    from
        Posts pt
        cross join lateral unnest(string_to_array(substring(pt.Tags from 2 for char_length(pt.Tags) - 2), '><')) as t(TagName)
    where pt.PostTypeId = 1
    group by ShortTagName
    having count(distinct pt.Id) > 50
    order by QCount desc
    limit 10
),
AnswersWithAvgScoreForQ as (
    select
       a.Id,
       a.ParentId as QuestionId,
       a.Score as AnswerScore,
       u.DisplayName as Answerer,
       ras.AvgScoreByUser,
       rank() over (partition by a.ParentId order by a.Score desc nulls last) as AnswerRank
    from 
      Posts a
      left join (
        select OwnerUserId, avg(cast(Score as float)) as AvgScoreByUser
        from Posts 
        where PostTypeId = 2
        group by OwnerUserId
      ) ras on a.OwnerUserId = ras.OwnerUserId
      left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2 and a.Score is not null
),
CompositeQuery as (
    select 
       u.Id as UserId, 
       u.DisplayName,
       u.Reputation,
       coalesce(count(b.Id),0) as TotalBadges,
       coalesce(sum(case when b.Class=1 then 1 else 0 end),0) as GoldBadges,
       coalesce(sum(case when b.Class=2 then 1 else 0 end),0) as SilverBadges,
       coalesce(sum(case when b.Class=3 then 1 else 0 end),0) as BronzeBadges,
       coalesce(saved1.PostCount,0) as UserPostCount,
       round(coalesce(saved1.AvgPostScore,0)::numeric,2) as AveragePostScore,
       coalesce(cc.CloseCount,0) as ClosedPosts,
       coalesce(cc.ReopenCount,0) as ReopenedPosts
    from Users u
    left join Badges b on b.UserId = u.Id
    left join UserAvgPostScore saved1 on saved1.OwnerUserId = u.Id
    left join CloseCounts cc on cc.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, saved1.PostCount, saved1.AvgPostScore, cc.CloseCount, cc.ReopenCount
),
JudgeCTE as (
    select 
        p.Id as PostId,
        p.Title,
        p.Score,
        l.RelatedPostId,
        l1.Name as LinkTypeName,
        ph.PostHistoryTypeId,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        case 
            when p.ClosedDate is not null then 'Closed'
            when (p.FavoriteCount > 50) then 'Highly Favorited'
            when p.Score > 10 then 'High Score'
            else 'Normal' 
        end as Status,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank
    from Posts p
    left join PostLinks l on l.PostId = p.Id
    left join LinkTypes l1 on l1.Id = l.LinkTypeId
    left join PostHistory ph on ph.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
),
FilteredPosts as (
    select * from JudgeCTE
    where Status != 'Normal'
    and (UserPostRank <= 5 or UserPostRank is null)
),
FinalSelections as (
    select
      cp.UserId,
      cp.DisplayName,
      cp.Reputation,
      cp.TotalBadges,
      cp.GoldBadges,
      cp.SilverBadges,
      cp.BronzeBadges,
      cp.UserPostCount,
      cp.AveragePostScore,
      cp.ClosedPosts,
      cp.ReopenedPosts,
      coalesce(fp.Title,'No Recent Upscale Post') as HighlightTitle,
      coalesce(fp.Score, 0) as HighlightPostScore,
      coalesce(fp.LinkTypeName, 'N/A') as CommonLinkType,
      tp.ShortTagName,
      tp.QCount,
      round(tp.AvgScore,2) as AvgTagScore,
      awas.AnswerScore,
      awas.AvgScoreByUser,
      awas.AnswerRank
    from CompositeQuery cp
    left join FilteredPosts fp on fp.OwnerUserId = cp.UserId
    left join TopTagUsage tp on tp.ShortTagName like '%sql%'
    left join AnswersWithAvgScoreForQ awas on awas.QuestionId = (
        select q.Id from Posts q where q.OwnerUserId = cp.UserId and q.PostTypeId=1 order by q.Score desc nulls last limit 1
    )
    where cp.Reputation > 1000
),
UnionedOutput as (
    select UserId, DisplayName, Reputation, TotalBadges, 'Badges Summary' as DataCategory, TotalBadges::varchar as DataValue from CompositeQuery
    union
    select UserId, DisplayName, Reputation, GoldBadges, 'Gold Badges' as DataCategory, GoldBadges::varchar as DataValue from CompositeQuery where GoldBadges > 0
    union 
    select UserId, DisplayName, Reputation, SilverBadges, 'Silver Badges' as DataCategory, SilverBadges::varchar as DataValue from CompositeQuery where SilverBadges > 0
    union
    select UserId, DisplayName, Reputation, BronzeBadges, 'Bronze Badges' as DataCategory, BronzeBadges::varchar as DataValue from CompositeQuery where BronzeBadges > 0
)

select
 
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.TotalBadges,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.UserPostCount,
    fs.AveragePostScore,
    fs.ClosedPosts,
    fs.ReopenedPosts,
    fs.HighlightTitle,
    fs.HighlightPostScore,
    fs.CommonLinkType,
    string_agg(distinct fs.ShortTagName, ',' order by fs.QCount desc) as PopularSqlTags,
    bool_or(fs.AnswerScore > fs.AvgScoreByUser) as HighScoreAnswer,
    row_number() over (order by fs.Reputation desc, fs.TotalBadges desc) as UserRank
  
from FinalSelections fs
where PopularSqlTags is not null or True
group by 
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.TotalBadges,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.UserPostCount,
    fs.AveragePostScore,
    fs.ClosedPosts,
    fs.ReopenedPosts,
    fs.HighlightTitle,
    fs.HighlightPostScore,
    fs.CommonLinkType,
    fs.AnswerScore,
    fs.AvgScoreByUser
order by 
    UserRank
limit 100;