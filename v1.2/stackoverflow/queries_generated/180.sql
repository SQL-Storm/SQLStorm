-- {"query": "180.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1784} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
    where r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven,
        max(u.Reputation) as MaxReputation,
        min(u.CreationDate) as FirstSeen,
        max(u.LastAccessDate) as LastSeen
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId in (8,9) -- BountyStart and BountyClose
    group by u.Id, u.DisplayName
),
PostScoreStats as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRank,
        avg(p.Score) over (partition by p.OwnerUserId) as AvgScore,
        count(*) over (partition by p.OwnerUserId) as TotalPostsByUser
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPostsWithAcceptedAnswers as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        u.DisplayName as OwnerName,
        au.DisplayName as AcceptedAnswerOwnerName
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    left join Users u on u.Id = p.OwnerUserId
    left join Users au on au.Id = a.OwnerUserId
    where p.PostTypeId = 1
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserEngagement as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyGiven,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.MaxReputation,
        ua.FirstSeen,
        ua.LastSeen,
        ps.AvgScore,
        ps.TotalPostsByUser
    from UserActivity ua
    left join UserBadgeSummary ub on ua.UserId = ub.UserId
    left join (
        select
            OwnerUserId,
            avg(Score) as AvgScore,
            count(*) as TotalPostsByUser
        from Posts
        where OwnerUserId is not null
        group by OwnerUserId
    ) ps on ua.UserId = ps.OwnerUserId
),
TopTagsByPopularity as (
    select
        t.TagName,
        t.Count,
        coalesce(pq.QuestionCount,0) as QuestionCount,
        coalesce(pa.AnswerCount,0) as AnswerCount,
        coalesce(avgScore.AvgScore,0) as AvgPostScore
    from Tags t
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
            count(*) as QuestionCount
        from Posts p
        where p.PostTypeId = 1
        group by Tag
    ) pq on pq.Tag = t.TagName
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
            count(*) as AnswerCount
        from Posts p
        where p.PostTypeId = 2
        group by Tag
    ) pa on pa.Tag = t.TagName
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
            avg(p.Score) as AvgScore
        from Posts p
        where p.PostTypeId in (1,2)
        group by Tag
    ) avgScore on avgScore.Tag = t.TagName
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    order by t.Count desc
    limit 20
)
select
    ue.UserId,
    ue.DisplayName,
    ue.QuestionsAsked,
    ue.AnswersGiven,
    ue.CommentsMade,
    ue.TotalBountyGiven,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.MaxReputation,
    ue.FirstSeen,
    ue.LastSeen,
    ue.AvgScore,
    ue.TotalPostsByUser,
    coalesce(crc.CloseCount,0) as TotalClosedPosts,
    string_agg(distinct concat_ws(': ', cr.CloseReason, crc.CloseCount), '; ') over () as CloseReasonsSummary,
    tpt.TagName as PopularTag,
    tpt.Count as TagCount,
    tpt.QuestionCount,
    tpt.AnswerCount,
    tpt.AvgPostScore,
    ph.Id as LastPostHistoryId,
    ph.PostHistoryTypeId,
    pht.Name as PostHistoryTypeName,
    ph.CreationDate as PostHistoryDate,
    ph.Comment as PostHistoryComment,
    ph.Text as PostHistoryText,
    pl.LinkTypeId,
    lt.Name as LinkTypeName,
    p.Title as PostTitle,
    p.Score as PostScore,
    p.ViewCount as PostViewCount,
    p.Tags as PostTags,
    row_number() over (partition by ue.UserId order by p.Score desc nulls last) as PostRankByUser
from UserEngagement ue
left join CloseReasonCounts crc on 1=1
left join CloseReasonTypes cr on cr.Id = crc.CloseCount
left join TopTagsByPopularity tpt on true
left join PostHistory ph on ph.UserId = ue.UserId
left join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
left join Posts p on p.Id = ph.PostId
left join PostLinks pl on pl.PostId = p.Id
left join LinkTypes lt on lt.Id = pl.LinkTypeId
where ue.QuestionsAsked > 5 and ue.AnswersGiven > 10
  and (p.Score > ue.AvgScore or p.Score is null)
  and (ph.PostHistoryTypeId in (10,11,12,13,14,15) or ph.PostHistoryTypeId is null)
order by ue.MaxReputation desc, ue.AnswersGiven desc, p.Score desc nulls last
limit 100;