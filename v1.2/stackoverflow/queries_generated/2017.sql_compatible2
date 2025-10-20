with RecursiveQuestions as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        pt.Name as PostType,
        dt.tag as TAG,
        u.DisplayName as OwnerName,
        row_number() over (partition by dt.tag order by p.Score desc nulls last, p.ViewCount desc) as RankPerTag
    from Posts p
    inner join PostTypes pt on p.PostTypeId = pt.Id
    left join lateral (
        select trim(both ' <&>' from tag) as tag
        from unnest(string_to_array(regexp_replace(p.Tags, '[<>]', '', 'g'), ' ')) as a(tag)
    ) dt on true
    left join Users u on p.OwnerUserId = u.Id
)
select
    QuestionId,
    Title,
    CreationDate,
    PostType,
    TAG,
    OwnerName,
    RankPerTag
from RecursiveQuestions
where RankPerTag = 1;