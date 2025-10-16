-- {"query": "522.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1288} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsModeratorOnly = 0 and t.Count > 10
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    where p.PostTypeId in (1,2)
),
FilteredPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        ph.Comment as CloseReason,
        ph.PostHistoryTypeId,
        ph.CreationDate as CloseDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    where p.PostTypeId = 1 and p.Score > 5
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserCommentStats as (
    select 
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.Text ilike '%sql%' then 1 else 0 end) as SqlMentions
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
ComplexUserSummary as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ucs.CommentCount,0) as CommentCount,
        coalesce(ucs.SqlMentions,0) as SqlMentions,
        case 
            when u.Reputation > 10000 then 'Expert'
            when u.Reputation between 1000 and 10000 then 'Intermediate'
            else 'Beginner'
        end as UserLevel,
        (select count(1) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Score > 10) as HighScoreQuestions,
        (select count(1) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2 and p.Score > 10) as HighScoreAnswers
    from Users u
    left join UserBadgeStats ubs on ubs.UserId = u.Id
    left join UserCommentStats ucs on ucs.UserId = u.Id
    where u.Reputation > 500
),
FinalResult as (
    select 
        cus.Id as UserId,
        cus.DisplayName,
        cus.Reputation,
        cus.UserLevel,
        cus.GoldBadges,
        cus.SilverBadges,
        cus.BronzeBadges,
        cus.CommentCount,
        cus.SqlMentions,
        cus.HighScoreQuestions,
        cus.HighScoreAnswers,
        fp.Id as QuestionId,
        fp.Title,
        fp.Score,
        fp.ViewCount,
        fp.CloseReason,
        dup.RelatedPostTitle as DuplicateOf,
        string_agg(distinct rt.TagName, ', ') as RelatedTags,
        (case 
            when fp.CloseReason is not null then 'Closed'
            else 'Open'
        end) as QuestionStatus,
        row_number() over (partition by cus.Id order by fp.Score desc) as QuestionRank
    from ComplexUserSummary cus
    left join FilteredPosts fp on fp.OwnerUserId = cus.Id
    left join DuplicateLinks dup on dup.PostId = fp.Id
    left join RecursiveTagHierarchy rt on rt.TagName = any(string_to_array(coalesce(fp.Tags,''), '><'))
    group by 
        cus.Id, cus.DisplayName, cus.Reputation, cus.UserLevel, cus.GoldBadges, cus.SilverBadges, cus.BronzeBadges, cus.CommentCount, cus.SqlMentions, cus.HighScoreQuestions, cus.HighScoreAnswers,
        fp.Id, fp.Title, fp.Score, fp.ViewCount, fp.CloseReason, dup.RelatedPostTitle
)
select * from FinalResult
where QuestionRank <= 3
order by Reputation desc, QuestionRank asc;