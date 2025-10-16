-- {"query": "167.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1595} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
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
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
),
PostAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByKnownUsers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
TopQuestionsWithAnswers as (
    select
        pas.*,
        urs.DisplayName as QuestionOwnerName,
        urs.Reputation as QuestionOwnerReputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        row_number() over (partition by pas.OwnerUserId order by pas.QuestionScore desc) as UserTopQuestionRank
    from PostAnswerStats pas
    left join UserReputationStats urs on pas.OwnerUserId = urs.UserId
    where pas.AnswerCount > 0 and pas.QuestionScore > 5
),
CommentsOnTopQuestions as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as CommentsByRegisteredUsers,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.PostId in (select QuestionId from TopQuestionsWithAnswers)
    group by c.PostId
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
UserVoteSummary as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast,
        count(distinct v.PostId) as DistinctPostsVoted
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.UserId
),
FinalSelection as (
    select
        tq.QuestionId,
        tq.Title,
        tq.QuestionScore,
        tq.ViewCount,
        tq.AnswerCount,
        tq.MaxAnswerScore,
        tq.AvgAnswerScore,
        coalesce(cotq.CommentCount, 0) as CommentCount,
        coalesce(cotq.CommentsByRegisteredUsers, 0) as CommentsByRegisteredUsers,
        coalesce(pld.DuplicateCount, 0) as DuplicateLinks,
        tq.QuestionOwnerName,
        tq.QuestionOwnerReputation,
        tq.GoldBadges,
        tq.SilverBadges,
        tq.BronzeBadges,
        urs.Location,
        urs.CreationDate as UserCreationDate,
        coalesce(uvs.UpVotesCast, 0) as UpVotesCast,
        coalesce(uvs.DownVotesCast, 0) as DownVotesCast,
        coalesce(uvs.FavoritesCast, 0) as FavoritesCast,
        coalesce(uvs.DistinctPostsVoted, 0) as DistinctPostsVoted,
        row_number() over (order by tq.QuestionScore desc, tq.ViewCount desc) as GlobalRank
    from TopQuestionsWithAnswers tq
    left join CommentsOnTopQuestions cotq on tq.QuestionId = cotq.PostId
    left join PostLinkDuplicates pld on tq.QuestionId = pld.PostId
    left join UserReputationStats urs on tq.OwnerUserId = urs.UserId
    left join UserVoteSummary uvs on tq.OwnerUserId = uvs.UserId
    where urs.Location is not null and urs.Location <> ''
)
select
    fs.GlobalRank,
    fs.QuestionId,
    fs.Title,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerCount,
    fs.MaxAnswerScore,
    round(fs.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    fs.CommentCount,
    fs.CommentsByRegisteredUsers,
    fs.DuplicateLinks,
    fs.QuestionOwnerName,
    fs.QuestionOwnerReputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.Location,
    fs.UserCreationDate,
    fs.UpVotesCast,
    fs.DownVotesCast,
    fs.FavoritesCast,
    fs.DistinctPostsVoted,
    case
        when fs.QuestionScore > 100 then 'Hot'
        when fs.QuestionScore between 50 and 100 then 'Trending'
        else 'Normal'
    end as PopularityCategory,
    substring(fs.Title from 1 for 50) || case when length(fs.Title) > 50 then '...' else '' end as ShortTitle,
    coalesce(rth.Path, 'NoTagHierarchy') as TagHierarchyPath
from FinalSelection fs
left join RecursiveTagHierarchy rth on position(rth.TagName in fs.Title) > 0
where fs.GlobalRank <= 50
order by fs.GlobalRank;