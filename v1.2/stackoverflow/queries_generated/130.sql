-- {"query": "130.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1588} 
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
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostWithVotesAndComments as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        coalesce(c.CommentCount, 0) as CommentCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        p.LastActivityDate
    from Posts p
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    left join (
        select
            PostId,
            count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
),
TopUsersByBadgeAndActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.TotalPostScore,
        ua.LastAccessDate,
        rank() over (order by ubc.GoldBadges desc, ua.TotalPostScore desc, u.Reputation desc) as UserRank
    from Users u
    left join (
        select
            UserId,
            coalesce(max(case when Class = 1 then BadgeCount end), 0) as GoldBadges,
            coalesce(max(case when Class = 2 then BadgeCount end), 0) as SilverBadges,
            coalesce(max(case when Class = 3 then BadgeCount end), 0) as BronzeBadges
        from UserBadgeCounts
        group by UserId
    ) ubc on ubc.UserId = u.Id
    left join UserActivityWindow ua on ua.UserId = u.Id
    where u.Reputation > 1000
),
QuestionsWithDuplicateLinks as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        pl.RelatedPostId as DuplicateOfQuestionId,
        dup.Title as DuplicateOfTitle,
        dup.Score as DuplicateOfScore
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    left join Posts dup on dup.Id = pl.RelatedPostId and dup.PostTypeId = 1
    where p.PostTypeId = 1
),
UserRecentActivity as (
    select
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        p.PostTypeId,
        p.Title,
        row_number() over (partition by ph.UserId order by ph.CreationDate desc) as rn
    from PostHistory ph
    join Posts p on p.Id = ph.PostId
    where ph.UserId is not null
),
UserRecentEdits as (
    select
        ura.UserId,
        ura.PostId,
        ura.PostHistoryTypeId,
        ura.CreationDate,
        ura.PostTypeId,
        ura.Title
    from UserRecentActivity ura
    where ura.rn <= 5 and ura.PostHistoryTypeId in (4,5,6)
),
FinalResult as (
    select
        t.UserRank,
        t.DisplayName,
        t.Reputation,
        t.GoldBadges,
        t.SilverBadges,
        t.BronzeBadges,
        t.QuestionsCount,
        t.AnswersCount,
        t.TotalPostScore,
        q.QuestionId,
        q.Title as QuestionTitle,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags as QuestionTags,
        q.DuplicateOfQuestionId,
        q.DuplicateOfTitle,
        q.DuplicateOfScore,
        ue.PostId as EditedPostId,
        ue.PostHistoryTypeId as EditType,
        ue.CreationDate as EditDate,
        ue.PostTypeId as EditedPostType,
        ue.Title as EditedPostTitle
    from TopUsersByBadgeAndActivity t
    left join QuestionsWithDuplicateLinks q on q.QuestionId in (
        select p.Id from Posts p where p.OwnerUserId = t.Id and p.PostTypeId = 1 limit 3
    )
    left join UserRecentEdits ue on ue.UserId = t.Id
    where t.UserRank <= 10
)
select
    UserRank,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    QuestionsCount,
    AnswersCount,
    TotalPostScore,
    QuestionId,
    coalesce(QuestionTitle, 'N/A') as QuestionTitle,
    QuestionScore,
    QuestionViews,
    coalesce(QuestionTags, '') as QuestionTags,
    DuplicateOfQuestionId,
    coalesce(DuplicateOfTitle, '') as DuplicateOfTitle,
    DuplicateOfScore,
    EditedPostId,
    EditType,
    EditDate,
    EditedPostType,
    EditedPostTitle
from FinalResult
order by UserRank, EditDate desc nulls last
limit 100;