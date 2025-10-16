-- {"query": "191.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2000} 
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
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsRequired = 1 and t.Id > r.Id
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date > current_date - interval '1 year'
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id,
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
    where u.Reputation > 1000
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate as QuestionCreation,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnsweredByRegisteredUsers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId
),
TopQuestionsWithComments as (
    select
        q.QuestionId,
        q.Title,
        q.QuestionCreation,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.MaxAnswerScore,
        q.AvgAnswerScore,
        q.AnsweredByRegisteredUsers,
        c.CommentCount,
        c.LatestCommentDate,
        c.LatestCommentUserId,
        u.DisplayName as LatestCommentUserName,
        u.Reputation as LatestCommentUserReputation
    from QuestionAnswerStats q
    left join (
        select
            PostId,
            count(*) as CommentCount,
            max(CreationDate) as LatestCommentDate,
            max(UserId) filter (where CreationDate = max(CreationDate) over (partition by PostId)) as LatestCommentUserId
        from Comments
        group by PostId
    ) c on c.PostId = q.QuestionId
    left join Users u on u.Id = c.LatestCommentUserId
    where q.AnswerCount > 5 and q.QuestionScore > 10
),
DuplicateQuestions as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as QuestionsLast30Days,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as AnswersLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 500
),
UserVoteSummary as (
    select
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId, vt.Name
),
UserEngagement as (
    select
        u.Id,
        u.DisplayName,
        coalesce(vs_up.VoteCount, 0) as UpVotesGiven,
        coalesce(vs_down.VoteCount, 0) as DownVotesGiven,
        coalesce(vs_fav.VoteCount, 0) as FavoritesGiven,
        coalesce(bc.GoldBadges, 0) as GoldBadges,
        coalesce(bc.SilverBadges, 0) as SilverBadges,
        coalesce(bc.BronzeBadges, 0) as BronzeBadges,
        u.Reputation
    from Users u
    left join (
        select UserId, VoteCount from UserVoteSummary where VoteTypeName = 'UpMod'
    ) vs_up on vs_up.UserId = u.Id
    left join (
        select UserId, VoteCount from UserVoteSummary where VoteTypeName = 'DownMod'
    ) vs_down on vs_down.UserId = u.Id
    left join (
        select UserId, VoteCount from UserVoteSummary where VoteTypeName = 'Favorite'
    ) vs_fav on vs_fav.UserId = u.Id
    left join (
        select
            UserId,
            sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
            sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
            sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
        from UserBadgeCounts
        group by UserId
    ) bc on bc.UserId = u.Id
    where u.Reputation > 1000
)
select
    tqwc.QuestionId,
    tqwc.Title,
    tqwc.QuestionCreation,
    tqwc.QuestionScore,
    tqwc.ViewCount,
    regexp_replace(tqwc.Tags, '[<>]', '', 'g') as CleanTags,
    tqwc.AnswerCount,
    tqwc.MaxAnswerScore,
    round(tqwc.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    tqwc.AnsweredByRegisteredUsers,
    tqwc.CommentCount,
    tqwc.LatestCommentDate,
    coalesce(tqwc.LatestCommentUserName, 'Anonymous') as LatestCommentUserName,
    coalesce(tqwc.LatestCommentUserReputation, 0) as LatestCommentUserReputation,
    dup.DuplicateQuestionId,
    dup.OriginalQuestionId,
    dup.DuplicateTitle,
    dup.OriginalTitle,
    dup.LinkCreationDate,
    ua.PostsLast30Days,
    ua.QuestionsLast30Days,
    ua.AnswersLast30Days,
    ue.UpVotesGiven,
    ue.DownVotesGiven,
    ue.FavoritesGiven,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.Reputation as UserReputation,
    rh.Level as TagHierarchyLevel,
    rh.Path as TagHierarchyPath
from TopQuestionsWithComments tqwc
left join DuplicateQuestions dup on dup.DuplicateQuestionId = tqwc.QuestionId
left join UserActivityWindow ua on ua.UserId = tqwc.OwnerUserId
left join UserEngagement ue on ue.Id = tqwc.OwnerUserId
left join RecursiveTagHierarchy rh on rh.TagName = split_part(split_part(tqwc.Tags, '><', 1), '<', 2)
where (tqwc.QuestionScore > 20 or tqwc.AnswerCount > 10)
  and (ue.GoldBadges > 0 or ue.Reputation > 5000)
order by tqwc.QuestionScore desc, tqwc.AnswerCount desc
limit 100;