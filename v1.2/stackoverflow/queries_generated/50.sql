-- {"query": "50.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1662} 
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
    join RecursiveTagHierarchy r on t2.Id <> all(r.Path)
    where t2.IsRequired = 1 and t2.Count < r.Count
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
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnswersWithOwner,
        sum(case when a.OwnerUserId is not null and a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as SelfAnsweredCount,
        max(case when a.Id = q.AcceptedAnswerId then a.Score else null end) as AcceptedAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        bool_or(lt.Name = 'Duplicate') as HasDuplicateLink
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
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
),
TopTagsByQuestionCount as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as QuestionCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by QuestionCount desc
    limit 10
),
QuestionsWithCommentsAndVotes as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        coalesce(v.Favorites, 0) as Favorites
    from Posts q
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = q.Id
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
            sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = q.Id
    where q.PostTypeId = 1
)
select
    urs.UserId,
    urs.DisplayName,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    urs.ReputationRank,
    pas.QuestionId,
    pas.Title as QuestionTitle,
    pas.QuestionCreationDate,
    pas.QuestionScore,
    pas.ViewCount,
    pas.TotalAnswers,
    pas.MaxAnswerScore,
    pas.AvgAnswerScore,
    pas.SelfAnsweredCount,
    pld.DuplicateCount,
    pld.HasDuplicateLink,
    qwc.CommentCount,
    qwc.UpVotes,
    qwc.DownVotes,
    qwc.Favorites,
    atq.Tag as TopTag,
    ua.PostsLast30Days,
    ua.QuestionsLast30Days,
    ua.AnswersLast30Days,
    case
        when urs.Reputation > 10000 and pas.TotalAnswers > 5 and pld.HasDuplicateLink then 'HighRepPopularDuplicateQuestion'
        when urs.Reputation <= 10000 and pas.TotalAnswers = 0 then 'LowRepUnansweredQuestion'
        else 'Other'
    end as UserQuestionCategory
from UserReputationStats urs
join PostAnswerStats pas on pas.OwnerUserId = urs.UserId
left join PostLinkDuplicates pld on pld.PostId = pas.QuestionId
left join QuestionsWithCommentsAndVotes qwc on qwc.QuestionId = pas.QuestionId
left join TopTagsByQuestionCount atq on atq.Tag = (select unnest(string_to_array(substring(pas.Tags from 2 for char_length(pas.Tags) - 2), '><')) limit 1)
left join UserActivityWindow ua on ua.UserId = urs.UserId
where urs.ReputationRank <= 100
order by urs.Reputation desc, pas.QuestionCreationDate desc
limit 100;