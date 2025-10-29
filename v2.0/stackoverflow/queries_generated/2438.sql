-- {"query": "2438.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1422} 
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
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Path || t2.Id
    from Tags t2
    join PostLinks pl on pl.PostId = t2.ExcerptPostId
    join RecursiveTagHierarchy r on pl.RelatedPostId = r.Id
    where not t2.Id = any(r.Path)
),
UserActivityStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as TotalUpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (
            partition by p.OwnerUserId, p.PostTypeId
            order by p.Score desc nulls last, p.ViewCount desc nulls last
        ) as PostRank
    from Posts p
    where p.PostTypeId in (1,2)
),
AcceptedAnswersWithLag as (
    select
        p.Id question_id,
        p.Title question_title,
        a.Id as answer_id,
        a.OwnerUserId answer_owner,
        a.CreationDate answer_date,
        a.Score answer_score,
        lag(a.CreationDate) over (partition by p.Id order by a.CreationDate) as PrevAnswerDate,
        coalesce(date_part('epoch', a.CreationDate - lag(a.CreationDate) over (partition by p.Id order by a.CreationDate)), 0) as SecondsSincePrevAnswer
    from Posts p
    join Posts a on a.ParentId = p.Id
    where p.PostTypeId = 1
),

PopularTags as (
    select
        unnest(string_to_array(replace(replace(substring(p.Tags from 2 for char_length(p.Tags)-2), '><', ','), '&lt;', '<'))) as TagName,
        count(*) as UsageCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by TagName
    having count(*) > 100
),

HighImpactComments as (
    select
        c.Id,
        c.PostId,
        c.UserId,
        c.Score,
        c.Text,
        p.Score as PostScore,
        rank() over (partition by c.PostId order by c.Score desc nulls last) as CommentRankPerPost,
        length(c.Text) as CommentLength
    from Comments c
    join Posts p on p.Id = c.PostId
    where c.Score is not null and c.Score > 5
),

FilteredUsersWithBadges as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.BadgeCount,
        uas.TotalUpVotes,
        uas.TotalDownVotes,
        array_agg(b.Name order by b.Date desc) filter (where b.Name is not null) as RecentBadges
    from UserActivityStats uas
    left join Badges b on b.UserId = uas.UserId
    where uas.BadgeCount > 10 and uas.Reputation > 1000
    group by uas.UserId, uas.DisplayName, uas.Reputation, uas.QuestionCount, uas.AnswerCount, uas.BadgeCount, uas.TotalUpVotes, uas.TotalDownVotes
)

select distinct
    fuwb.UserId,
    fuwb.DisplayName,
    fuwb.Reputation,
    fuwb.QuestionCount,
    fuwb.AnswerCount,
    fuwb.BadgeCount,
    fuwb.TotalUpVotes,
    fuwb.TotalDownVotes,
    case when fuwb.TotalDownVotes = 0 then null else round(cast(fuwb.TotalUpVotes as numeric)/fuwb.TotalDownVotes,2) end as UpDownVoteRatio,
    p.Title as TopQuestionTitle,
    p.Score as TopQuestionScore,
    p.ViewCount as TopQuestionViews,
    a.answer_id,
    a.answer_score,
    a.answer_date,
    a.SecondsSincePrevAnswer,
    hc.Text as TopCommentText,
    hc.Score as TopCommentScore,
    string_agg(distinct pt.TagName, ',') as CommonPopularTags,
    string_agg(distinct rt.TagName, ',') as RecursiveRequiredTags
from FilteredUsersWithBadges fuwb
left join RankedPosts p on p.OwnerUserId = fuwb.UserId and p.PostRank = 1 and p.PostTypeId = 1
left join AcceptedAnswersWithLag a on a.answer_owner = fuwb.UserId
left join HighImpactComments hc on hc.UserId = fuwb.UserId and hc.CommentRankPerPost = 1
left join PopularTags pt on pt.TagName = any(string_to_array(p.Tags, '><'))
left join RecursiveTagHierarchy rt on rt.TagName = any(string_to_array(p.Tags, '><'))
where fuwb.Reputation > 5000
group by
    fuwb.UserId,
    fuwb.DisplayName,
    fuwb.Reputation,
    fuwb.QuestionCount,
    fuwb.AnswerCount,
    fuwb.BadgeCount,
    fuwb.TotalUpVotes,
    fuwb.TotalDownVotes,
    p.Title,
    p.Score,
    p.ViewCount,
    a.answer_id,
    a.answer_score,
    a.answer_date,
    a.SecondsSincePrevAnswer,
    hc.Text,
    hc.Score
having count(distinct hc.Id) > 0
order by fuwb.Reputation desc, fuwb.BadgeCount desc, p.Score desc
limit 100;