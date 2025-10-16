-- {"query": "148.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1723} 
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
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and not t.TagName = any(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnswersWithOwner,
        sum(case when a.Score > q.Score then 1 else 0 end) as AnswersBetterThanQuestion
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopQuestionsWithComments as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(c.Id) as CommentCount,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters,
        row_number() over (order by p.Score desc, p.ViewCount desc) as Rank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Score, p.ViewCount, p.Tags
    having count(c.Id) > 5
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserReputationChange as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.CreationDate::date as PostDate,
        sum(case when v.VoteTypeId = 2 then 10 when v.VoteTypeId = 3 then -2 else 0 end) as ReputationChange
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id and v.CreationDate::date = p.CreationDate::date
    group by u.Id, u.DisplayName, p.CreationDate::date
),
UserReputationChangeCumulative as (
    select
        UserId,
        DisplayName,
        PostDate,
        sum(ReputationChange) over (partition by UserId order by PostDate rows between unbounded preceding and current row) as CumulativeReputation
    from UserReputationChange
)
select
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.Location,
    pqs.Title as TopQuestionTitle,
    pqs.AnswerCount,
    pqs.MaxAnswerScore,
    pqs.AvgAnswerScore,
    pqs.AnswersBetterThanQuestion,
    pcr.CloseReasonName,
    twc.CommentCount,
    twc.Commenters,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    urc.PostDate,
    urc.ReputationChange,
    urcc.CumulativeReputation,
    string_agg(distinct rth.TagName, ', ') as RelatedTagsPath
from UserReputationStats u
left join PostAnswerStats pqs on pqs.OwnerUserId = u.UserId
left join PostCloseReasons pcr on pcr.PostId = pqs.QuestionId
left join TopQuestionsWithComments twc on twc.Id = pqs.QuestionId
left join DuplicateLinks dup on dup.PostId = pqs.QuestionId
left join UserReputationChange urc on urc.UserId = u.UserId
left join UserReputationChangeCumulative urcc on urcc.UserId = u.UserId and urcc.PostDate = urc.PostDate
left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(pqs.Tags, '')) > 0
where u.Reputation > 10000
  and (pqs.AnswerCount > 5 or pqs.AnswersBetterThanQuestion > 0)
  and (pcr.CloseReasonName is null or pcr.CloseReasonName not in ('Duplicate', 'Off-topic'))
group by
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.Location,
    pqs.Title,
    pqs.AnswerCount,
    pqs.MaxAnswerScore,
    pqs.AvgAnswerScore,
    pqs.AnswersBetterThanQuestion,
    pcr.CloseReasonName,
    twc.CommentCount,
    twc.Commenters,
    dup.PostTitle,
    dup.RelatedPostTitle,
    urc.PostDate,
    urc.ReputationChange,
    urcc.CumulativeReputation
order by u.Reputation desc, pqs.AnswerCount desc
limit 100;