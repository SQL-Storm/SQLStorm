-- {"query": "2708.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1340} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        p.Id as ExcerptPostId,
        p.Title as ExcerptTitle,
        p.Score as ExcerptScore,
        1 as Level
    from Tags t
    left join Posts p on t.ExcerptPostId = p.Id
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        p2.Id,
        p2.Title,
        p2.Score,
        r.Level + 1
    from Tags t2
    join Posts p2 on t2.ExcerptPostId = p2.Id
    join RecursiveTagHierarchy r on r.Id <> t2.Id
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and r.Level < 3
),
UserBadgesRanked as (
    select 
        b.UserId,
        b.Name,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as rn
    from Badges b
    where b.Class in (1, 2, 3)
),
TopUsersByScore as (
    select distinct 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        coalesce(u.Location, 'Unknown') as Location,
        u.CreationDate,
        sum(p.Score) over (partition by u.Id) as TotalPostScore,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as UpVotesGiven,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3) as DownVotesGiven,
        (select count(*) from Comments c where c.UserId = u.Id) as CommentsMade,
        (select string_agg(distinct b.Name, ', ') from Badges b where b.UserId = u.Id and b.Class = 1) as GoldBadges,
        (select string_agg(distinct b.Name, ', ') from Badges b where b.UserId = u.Id and b.Class = 2) as SilverBadges,
        (select string_agg(distinct b.Name, ', ') from Badges b where b.UserId = u.Id and b.Class = 3) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
TopQuestionsWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        a.OwnerUserId as AnswerOwner,
        u.DisplayName as AnswererName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1 and q.Score > 10
),
FinalResult as (
    select 
        tu.DisplayName,
        tu.Reputation,
        tu.Location,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.TotalPostScore,
        tu.UpVotesGiven,
        tu.DownVotesGiven,
        tu.CommentsMade,
        coalesce(tu.GoldBadges, '') as GoldBadges,
        coalesce(tu.SilverBadges, '') as SilverBadges,
        coalesce(tu.BronzeBadges, '') as BronzeBadges,
        q.Title as TopQuestionTitle,
        q.QuestionScore,
        q.QuestionViews,
        q.Tags as QuestionTags,
        q.AnswerId,
        q.AnswerScore,
        q.AnswererName,
        case 
            when q.AnswerScore is null then 'No Answers'
            when q.AnswerScore > 5 then 'Highly Rated Answer'
            else 'Answer Present'
        end as AnswerQuality,
        case 
            when strpos(q.Tags, '<sql>') > 0 then 'Has SQL Tag'
            else 'No SQL Tag'
        end as HasSQLTag,
        rh.Level as TagExcerptLevel,
        rh.TagName as TagExcerptName,
        rh.ExcerptTitle as TagExcerptPostTitle,
        rh.ExcerptScore as TagExcerptScore
    from TopUsersByScore tu
    left join TopQuestionsWithAnswers q on q.AnswerRank = 1 and q.QuestionScore > 20 and q.AnswerScore is not null
    left join RecursiveTagHierarchy rh on rh.TagName = substring(split_part(split_part(q.Tags, '><',1), '<', 2), 1, 35)
    where tu.AnswerCount > 10 and tu.QuestionCount >= 5
    order by tu.TotalPostScore desc, q.QuestionScore desc nulls last
    limit 50
)
select * from FinalResult
union
select 
    'System' as DisplayName,
    999999 as Reputation,
    'Unknown' as Location,
    0 as QuestionCount,
    0 as AnswerCount,
    0 as TotalPostScore,
    0 as UpVotesGiven,
    0 as DownVotesGiven,
    0 as CommentsMade,
    '' as GoldBadges,
    '' as SilverBadges,
    '' as BronzeBadges,
    'Dummy Question Title' as TopQuestionTitle,
    0 as QuestionScore,
    0 as QuestionViews,
    '' as QuestionTags,
    null as AnswerId,
    null as AnswerScore,
    null as AnswererName,
    'No Answers' as AnswerQuality,
    'No SQL Tag' as HasSQLTag,
    0 as TagExcerptLevel,
    null as TagExcerptName,
    null as TagExcerptPostTitle,
    null as TagExcerptScore;