with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = true

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
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on not (t2.Id = any(r.Path))
    where t2.IsRequired = true and t2.Count < r.Count
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
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegisteredUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as CommentsByRegisteredUsers,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
QuestionVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        count(*) over (partition by u.Id order by p.CreationDate rows between 365 preceding and current row) as PostsLastYear
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u2 on u2.Id = p2.OwnerUserId
),
QuestionTagExplode as (
    select
        p.Id as QuestionId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagPopularity as (
    select
        qte.Tag,
        count(distinct qte.QuestionId) as QuestionCount,
        avg(p.Score) as AvgQuestionScore,
        max(p.Score) as MaxQuestionScore
    from QuestionTagExplode qte
    join Posts p on p.Id = qte.QuestionId
    group by qte.Tag
),
UserTopTags as (
    select
        u.Id as UserId,
        qte.Tag,
        count(*) as TagQuestionCount,
        row_number() over (partition by u.Id order by count(*) desc) as TagRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    join QuestionTagExplode qte on qte.QuestionId = p.Id
    group by u.Id, qte.Tag
)
select
    urs.UserId,
    urs.DisplayName,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    urs.ReputationRank,
    ta.Id as QuestionId,
    ta.Title,
    ta.Score as QuestionScore,
    ta.ViewCount,
    ta.Tags,
    coalesce(AnswerStats.AnswerCount, 0) as AnswerCount,
    coalesce(AnswerStats.AvgAnswerScore, 0) as AvgAnswerScore,
    coalesce(AnswerStats.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(qcr.CloseReasonName, 'Open') as CloseReason,
    coalesce(qc.CommentCount, 0) as CommentCount,
    coalesce(qc.CommentsByRegisteredUsers, 0) as CommentsByRegisteredUsers,
    coalesce(qv.UpVotes, 0) as UpVotes,
    coalesce(qv.DownVotes, 0) as DownVotes,
    coalesce(qv.Favorites, 0) as Favorites,
    ua.PostsLast30Days,
    ua.PostsLastYear,
    tp.Tag,
    tp.QuestionCount as TagQuestionCount,
    tp.AvgQuestionScore as TagAvgQuestionScore,
    tp.MaxQuestionScore as TagMaxQuestionScore,
    ut.TagRank as UserTagRank,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.PostOwner as DuplicatePostOwner,
    dl.RelatedPostOwner as DuplicateRelatedPostOwner
from UserReputationStats urs
join TopQuestions ta on ta.OwnerUserId = urs.UserId and ta.UserTopQuestionRank = 1
left join AnswerStats AnswerStats on AnswerStats.QuestionId = ta.Id
left join QuestionCloseReasons qcr on qcr.PostId = ta.Id
left join QuestionComments qc on qc.PostId = ta.Id
left join QuestionVotes qv on qv.PostId = ta.Id
left join UserActivityWindow ua on ua.UserId = urs.UserId and ua.PostId = ta.Id
left join QuestionTagExplode qte on qte.QuestionId = ta.Id
left join TagPopularity tp on tp.Tag = qte.Tag
left join UserTopTags ut on ut.UserId = urs.UserId and ut.Tag = tp.Tag
left join DuplicateLinks dl on dl.PostId = ta.Id
where urs.Reputation > 10000
  and (qcr.CloseReasonName is null or qcr.CloseReasonName = 'Open')
  and (tp.QuestionCount > 50 or tp.QuestionCount is null)
order by urs.ReputationRank, ta.Score desc
limit 100;