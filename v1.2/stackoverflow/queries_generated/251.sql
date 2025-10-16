-- {"query": "251.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2015} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.TagBased = 0 or b.TagBased is null
),
TopUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        count(distinct b.Id) as BadgeCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select 
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on p.Id = v.PostId
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
    having count(distinct p.Id) filter (where p.PostTypeId = 1) > 10
),
PostActivity as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    where p.PostTypeId in (1,2)
),
PostWithHistory as (
    select 
        p.PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.Comment as HistoryComment,
        ph.Text as HistoryText
    from PostActivity p
    left join PostHistory ph on ph.PostId = p.PostId
    and ph.CreationDate = (
        select max(ph2.CreationDate) 
        from PostHistory ph2 
        where ph2.PostId = p.PostId
    )
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerName,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    join Posts rp on rp.Id = pl.RelatedPostId
    left join Users u on u.Id = p.OwnerUserId
    where pl.LinkTypeId = 3
),
UserActivityWindow as (
    select 
        ua.UserId,
        ua.PostId,
        ua.CreationDate,
        count(*) over (partition by ua.UserId order by ua.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by ua.UserId order by ua.CreationDate rows between 30 preceding and current row) as QuestionsLast30Days,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by ua.UserId order by ua.CreationDate rows between 30 preceding and current row) as AnswersLast30Days
    from (
        select OwnerUserId as UserId, Id as PostId, CreationDate from Posts where OwnerUserId is not null
    ) ua
    join Posts p on p.Id = ua.PostId
),
ComplexTagAnalysis as (
    select 
        t.TagName,
        t.Count,
        coalesce(qs.QuestionCount,0) as QuestionCount,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(avgScore.AvgScore,0) as AvgPostScore,
        case when t.IsModeratorOnly = 1 then 'ModeratorOnly' else 'General' end as TagCategory,
        case when t.IsRequired = 1 then 'Required' else 'Optional' end as TagRequirement,
        substring(t.TagName from 1 for 1) as TagFirstChar
    from Tags t
    left join (
        select unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName, count(*) as QuestionCount
        from Posts p
        where p.PostTypeId = 1
        group by TagName
    ) qs on qs.TagName = t.TagName
    left join (
        select unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName, count(*) as AnswerCount
        from Posts p
        where p.PostTypeId = 2
        group by TagName
    ) ans on ans.TagName = t.TagName
    left join (
        select unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName, avg(p.Score) as AvgScore
        from Posts p
        group by TagName
    ) avgScore on avgScore.TagName = t.TagName
)
select 
    tu.DisplayName as UserName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalUpVotes,
    tu.TotalDownVotes,
    tu.BadgeCount,
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.AcceptedAnswerId,
    r.AnswerCount as PostAnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    r.ClosedDate,
    r.LastActivityDate,
    ph.PostHistoryTypeId,
    ph.HistoryDate,
    ph.EditorUserId,
    ph.EditorDisplayName,
    ph.HistoryComment,
    ph.HistoryText,
    dup.RelatedPostId as DuplicateOfPostId,
    dup.RelatedPostTitle as DuplicateOfPostTitle,
    ua.PostsLast30Days,
    ua.QuestionsLast30Days,
    ua.AnswersLast30Days,
    cta.TagName,
    cta.Count as TagUsageCount,
    cta.QuestionCount as TagQuestionCount,
    cta.AnswerCount as TagAnswerCount,
    cta.AvgPostScore as TagAverageScore,
    cta.TagCategory,
    cta.TagRequirement,
    cta.TagFirstChar,
    rub.BadgeName,
    rub.Class as BadgeClass,
    case 
        when r.ClosedDate is not null then 'Closed' 
        when r.AcceptedAnswerId is not null then 'Answered' 
        else 'Open' 
    end as PostStatus,
    length(coalesce(r.Title, '')) + length(coalesce(r.Tags, '')) as TitleTagLength,
    case when r.Score > 0 then log(r.Score + 1) else 0 end as LogScore,
    case when r.ViewCount > 0 then log(r.ViewCount + 1) else 0 end as LogViewCount,
    case when r.AnswerCount > 0 then r.Score::float / r.AnswerCount else null end as ScorePerAnswer,
    case when r.FavoriteCount > 0 then r.FavoriteCount::float / nullif(r.ViewCount,0) else 0 end as FavoriteRatio,
    case when r.Tags is null then 0 else array_length(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><'), 1) end as TagCount
from TopUsers tu
join PostActivity r on r.OwnerUserId = tu.Id and r.RecentPostRank <= 5
left join PostWithHistory ph on ph.PostId = r.PostId
left join DuplicateLinks dup on dup.PostId = r.PostId
left join UserActivityWindow ua on ua.UserId = tu.Id and ua.PostId = r.PostId
left join ComplexTagAnalysis cta on cta.TagName = (select unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) limit 1)
left join RecursiveUserBadges rub on rub.UserId = tu.Id and rub.BadgeRank = 1
where tu.Reputation > 1000
order by tu.Reputation desc, r.CreationDate desc
limit 100;