-- {"query": "205.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1614} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and t2.Id <> r.Id and not t2.TagName = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationRanks as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank,
        dense_rank() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc) as YearlyReputationRank
    from Users u
),
PostScoreStats as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        sum(case when p.Score > 0 then 1 else 0 end) as PositiveScoreCount,
        sum(case when p.Score < 0 then 1 else 0 end) as NegativeScoreCount
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId, p.PostTypeId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswererName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator,
        lt.Name as LinkTypeName
    from PostLinks pl
    left join Users u on u.Id = (select ph.UserId from PostHistory ph where ph.PostId = pl.PostId order by ph.CreationDate asc limit 1)
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        count(distinct b.Id) as BadgesEarned,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    ur.Id as UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.ReputationRank,
    ur.YearlyReputationRank,
    coalesce(ubc_badge_gold.BadgeCount, 0) as GoldBadges,
    coalesce(ubc_badge_silver.BadgeCount, 0) as SilverBadges,
    coalesce(ubc_badge_bronze.BadgeCount, 0) as BronzeBadges,
    pasq.PostCount as QuestionCount,
    pasa.PostCount as AnswerCount,
    pasq.AvgScore as AvgQuestionScore,
    pasa.AvgScore as AvgAnswerScore,
    tas.AnswerCountForTopQuestions,
    ua.TotalPosts,
    ua.TotalComments,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.BadgesEarned,
    ua.LastPostDate,
    ua.LastCommentDate,
    string_agg(distinct dt.TagName, ', ') as RequiredTags,
    dl.DuplicateLinkCount
from UserReputationRanks ur
left join UserBadgeCounts ubc_badge_gold on ubc_badge_gold.UserId = ur.Id and ubc_badge_gold.Class = 1
left join UserBadgeCounts ubc_badge_silver on ubc_badge_silver.UserId = ur.Id and ubc_badge_silver.Class = 2
left join UserBadgeCounts ubc_badge_bronze on ubc_badge_bronze.UserId = ur.Id and ubc_badge_bronze.Class = 3
left join PostScoreStats pasq on pasq.OwnerUserId = ur.Id and pasq.PostTypeId = 1
left join PostScoreStats pasa on pasa.OwnerUserId = ur.Id and pasa.PostTypeId = 2
left join (
    select
        q.OwnerUserId,
        count(a.Id) as AnswerCountForTopQuestions
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 10
    group by q.OwnerUserId
) tas on tas.OwnerUserId = ur.Id
left join UserActivitySummary ua on ua.UserId = ur.Id
left join (
    select
        pl.PostId,
        count(*) as DuplicateLinkCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
) dl on dl.PostId = ur.Id
left join RecursiveTagHierarchy dt on dt.Level = 1
where ur.Reputation > 1000
group by
    ur.Id,
    ur.DisplayName,
    ur.Reputation,
    ur.ReputationRank,
    ur.YearlyReputationRank,
    ubc_badge_gold.BadgeCount,
    ubc_badge_silver.BadgeCount,
    ubc_badge_bronze.BadgeCount,
    pasq.PostCount,
    pasa.PostCount,
    pasq.AvgScore,
    pasa.AvgScore,
    tas.AnswerCountForTopQuestions,
    ua.TotalPosts,
    ua.TotalComments,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.BadgesEarned,
    ua.LastPostDate,
    ua.LastCommentDate,
    dl.DuplicateLinkCount
order by ur.ReputationRank
limit 100;